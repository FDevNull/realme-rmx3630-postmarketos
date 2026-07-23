// SPDX-License-Identifier: GPL-2.0
/*
 * Minimal battery power_supply for the Realme 10 4G (RMX3630).
 *
 * The stock mt6358_battery module depends on the Android/Oplus charging stack,
 * which is unsafe to load in the postmarketOS userspace. This driver binds to
 * the otherwise unused gauge DT node and reads its existing MT635x AUXADC
 * battery-voltage channel without initializing oplus_chg.
 */

#include <linux/iio/consumer.h>
#include <linux/jiffies.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/of_platform.h>
#include <linux/platform_device.h>
#include <linux/power_supply.h>
#include <linux/workqueue.h>

#define RMX3630_UPDATE_INTERVAL (30 * HZ)
#define RMX3630_DESIGN_UAH 5000000

struct rmx3630_battery {
	struct device *dev;
	struct iio_channel *vbat;
	struct power_supply *psy;
	struct delayed_work update_work;
	int voltage_uv;
	int capacity;
};

struct voltage_capacity {
	int mv;
	int percent;
};

/*
 * Conservative resting-voltage estimate for the phone's single-cell
 * high-voltage Li-ion pack. It is intentionally monotonic and can later be
 * replaced by coulomb-counter integration without changing the UPower ABI.
 */
static const struct voltage_capacity rmx3630_curve[] = {
	{ 3300,   0 },
	{ 3500,   5 },
	{ 3600,  10 },
	{ 3700,  20 },
	{ 3800,  35 },
	{ 3900,  50 },
	{ 4000,  65 },
	{ 4100,  78 },
	{ 4200,  88 },
	{ 4300,  95 },
	{ 4400, 100 },
};

static int rmx3630_capacity_from_mv(int mv)
{
	int i;

	if (mv <= rmx3630_curve[0].mv)
		return rmx3630_curve[0].percent;

	for (i = 1; i < ARRAY_SIZE(rmx3630_curve); i++) {
		const struct voltage_capacity *low = &rmx3630_curve[i - 1];
		const struct voltage_capacity *high = &rmx3630_curve[i];

		if (mv <= high->mv)
			return low->percent +
				(mv - low->mv) *
				(high->percent - low->percent) /
				(high->mv - low->mv);
	}

	return 100;
}

static int rmx3630_read_voltage(struct rmx3630_battery *battery)
{
	int mv;
	int ret;

	ret = iio_read_channel_processed(battery->vbat, &mv);
	if (ret < 0)
		return ret;

	/* MT635x AUXADC reports this channel in millivolts. */
	if (mv < 2500 || mv > 5000) {
		dev_warn_ratelimited(battery->dev,
				     "implausible AUXADC battery voltage: %d\n",
				     mv);
		return -ERANGE;
	}

	battery->voltage_uv = mv * 1000;
	battery->capacity = rmx3630_capacity_from_mv(mv);
	return 0;
}

static enum power_supply_property rmx3630_battery_properties[] = {
	POWER_SUPPLY_PROP_STATUS,
	POWER_SUPPLY_PROP_HEALTH,
	POWER_SUPPLY_PROP_PRESENT,
	POWER_SUPPLY_PROP_TECHNOLOGY,
	POWER_SUPPLY_PROP_CAPACITY,
	POWER_SUPPLY_PROP_CAPACITY_LEVEL,
	POWER_SUPPLY_PROP_VOLTAGE_NOW,
	POWER_SUPPLY_PROP_CHARGE_FULL,
	POWER_SUPPLY_PROP_CHARGE_FULL_DESIGN,
	POWER_SUPPLY_PROP_CHARGE_NOW,
	POWER_SUPPLY_PROP_MODEL_NAME,
	POWER_SUPPLY_PROP_MANUFACTURER,
};

static int rmx3630_battery_get_property(struct power_supply *psy,
					enum power_supply_property property,
					union power_supply_propval *value)
{
	struct rmx3630_battery *battery = power_supply_get_drvdata(psy);

	switch (property) {
	case POWER_SUPPLY_PROP_STATUS:
		value->intval = POWER_SUPPLY_STATUS_DISCHARGING;
		break;
	case POWER_SUPPLY_PROP_HEALTH:
		value->intval = POWER_SUPPLY_HEALTH_GOOD;
		break;
	case POWER_SUPPLY_PROP_PRESENT:
		value->intval = 1;
		break;
	case POWER_SUPPLY_PROP_TECHNOLOGY:
		value->intval = POWER_SUPPLY_TECHNOLOGY_LION;
		break;
	case POWER_SUPPLY_PROP_CAPACITY:
		value->intval = battery->capacity;
		break;
	case POWER_SUPPLY_PROP_CAPACITY_LEVEL:
		if (battery->capacity <= 5)
			value->intval = POWER_SUPPLY_CAPACITY_LEVEL_CRITICAL;
		else if (battery->capacity <= 15)
			value->intval = POWER_SUPPLY_CAPACITY_LEVEL_LOW;
		else if (battery->capacity >= 100)
			value->intval = POWER_SUPPLY_CAPACITY_LEVEL_FULL;
		else
			value->intval = POWER_SUPPLY_CAPACITY_LEVEL_NORMAL;
		break;
	case POWER_SUPPLY_PROP_VOLTAGE_NOW:
		value->intval = battery->voltage_uv;
		break;
	case POWER_SUPPLY_PROP_CHARGE_FULL:
	case POWER_SUPPLY_PROP_CHARGE_FULL_DESIGN:
		value->intval = RMX3630_DESIGN_UAH;
		break;
	case POWER_SUPPLY_PROP_CHARGE_NOW:
		value->intval = RMX3630_DESIGN_UAH * battery->capacity / 100;
		break;
	case POWER_SUPPLY_PROP_MODEL_NAME:
		value->strval = "RMX3630 battery";
		break;
	case POWER_SUPPLY_PROP_MANUFACTURER:
		value->strval = "Realme";
		break;
	default:
		return -EINVAL;
	}

	return 0;
}

static const struct power_supply_desc rmx3630_battery_desc = {
	.name = "battery",
	.type = POWER_SUPPLY_TYPE_BATTERY,
	.properties = rmx3630_battery_properties,
	.num_properties = ARRAY_SIZE(rmx3630_battery_properties),
	.get_property = rmx3630_battery_get_property,
};

static void rmx3630_battery_update(struct work_struct *work)
{
	struct rmx3630_battery *battery =
		container_of(to_delayed_work(work),
			     struct rmx3630_battery, update_work);
	int old_capacity = battery->capacity;
	int old_voltage = battery->voltage_uv;

	if (!rmx3630_read_voltage(battery) &&
	    (old_capacity != battery->capacity ||
	     old_voltage != battery->voltage_uv))
		power_supply_changed(battery->psy);

	schedule_delayed_work(&battery->update_work,
			      RMX3630_UPDATE_INTERVAL);
}

static int rmx3630_battery_probe(struct platform_device *pdev)
{
	struct power_supply_config config = {};
	struct rmx3630_battery *battery;
	int ret;

	battery = devm_kzalloc(&pdev->dev, sizeof(*battery), GFP_KERNEL);
	if (!battery)
		return -ENOMEM;

	battery->dev = &pdev->dev;
	battery->vbat = devm_iio_channel_get(&pdev->dev,
					     "pmic_battery_voltage");
	if (IS_ERR(battery->vbat)) {
		ret = PTR_ERR(battery->vbat);
		dev_err(&pdev->dev, "failed to acquire battery AUXADC: %d\n",
			ret);
		return ret;
	}

	ret = rmx3630_read_voltage(battery);
	if (ret) {
		dev_err(&pdev->dev, "failed to read battery AUXADC: %d\n", ret);
		return ret;
	}

	config.drv_data = battery;
	config.of_node = pdev->dev.of_node;
	battery->psy = power_supply_register(&pdev->dev,
					     &rmx3630_battery_desc,
					     &config);
	if (IS_ERR(battery->psy)) {
		ret = PTR_ERR(battery->psy);
		dev_err(&pdev->dev, "failed to register power supply: %d\n", ret);
		return ret;
	}

	platform_set_drvdata(pdev, battery);
	INIT_DELAYED_WORK(&battery->update_work, rmx3630_battery_update);
	schedule_delayed_work(&battery->update_work,
			      RMX3630_UPDATE_INTERVAL);

	dev_info(&pdev->dev, "battery registered: %d mV, %d%%\n",
		 battery->voltage_uv / 1000, battery->capacity);
	return 0;
}

static int __init rmx3630_battery_init(void)
{
	struct platform_device *pdev;
	struct device_node *node;
	int ret;

	node = of_find_node_by_name(NULL, "mtk_gauge");
	if (!node) {
		pr_err("rmx3630-battery: mtk_gauge DT node not found\n");
		return -ENODEV;
	}

	pdev = of_find_device_by_node(node);
	if (!pdev) {
		pr_err("rmx3630-battery: mtk_gauge platform device not found\n");
		return -ENODEV;
	}

	ret = rmx3630_battery_probe(pdev);
	pr_info("rmx3630-battery: direct gauge probe returned %d\n", ret);
	return ret;
}
module_init(rmx3630_battery_init);

MODULE_AUTHOR("RMX3630 postmarketOS port");
MODULE_DESCRIPTION("Minimal RMX3630 AUXADC battery power_supply");
MODULE_LICENSE("GPL");
