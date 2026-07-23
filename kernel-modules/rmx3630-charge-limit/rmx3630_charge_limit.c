// SPDX-License-Identifier: GPL-2.0
#include <linux/i2c.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/power_supply.h>
#include <linux/workqueue.h>

#define BQ25890_REG03 0x03
#define BQ25890_CHG_CONFIG BIT(4)
#define LIMIT_PERCENT 80
#define RESUME_PERCENT 75
#define POLL_INTERVAL (30 * HZ)

static struct i2c_client *charger;
static struct power_supply *battery;
static struct delayed_work limit_work;
static bool limited;

static void rmx3630_apply_charge_limit(struct work_struct *work)
{
	union power_supply_propval value;
	int capacity;
	int reg;
	int ret;

	ret = power_supply_get_property(battery, POWER_SUPPLY_PROP_CAPACITY,
					&value);
	if (ret)
		goto again;
	capacity = value.intval;

	if ((!limited && capacity < LIMIT_PERCENT) ||
	    (limited && capacity > RESUME_PERCENT))
		goto again;

	reg = i2c_smbus_read_byte_data(charger, BQ25890_REG03);
	if (reg < 0)
		goto again;

	if (!limited && capacity >= LIMIT_PERCENT) {
		ret = i2c_smbus_write_byte_data(charger, BQ25890_REG03,
					       reg & ~BQ25890_CHG_CONFIG);
		if (!ret) {
			limited = true;
			pr_info("rmx3630-charge-limit: charging stopped at %d%%\n",
				capacity);
		}
	} else if (limited && capacity <= RESUME_PERCENT) {
		ret = i2c_smbus_write_byte_data(charger, BQ25890_REG03,
					       reg | BQ25890_CHG_CONFIG);
		if (!ret) {
			limited = false;
			pr_info("rmx3630-charge-limit: charging resumed at %d%%\n",
				capacity);
		}
	}

again:
	schedule_delayed_work(&limit_work, POLL_INTERVAL);
}

static int __init rmx3630_charge_limit_init(void)
{
	struct device_node *node;

	node = of_find_node_by_name(NULL, "bq2589x");
	if (!node)
		return -ENODEV;

	charger = of_find_i2c_device_by_node(node);
	if (!charger)
		return -ENODEV;

	battery = power_supply_get_by_name("battery");
	if (!battery)
		return -EPROBE_DEFER;

	INIT_DELAYED_WORK(&limit_work, rmx3630_apply_charge_limit);
	schedule_delayed_work(&limit_work, 0);
	pr_info("rmx3630-charge-limit: active, limit=%d%% resume=%d%%\n",
		LIMIT_PERCENT, RESUME_PERCENT);
	return 0;
}
module_init(rmx3630_charge_limit_init);

MODULE_AUTHOR("RMX3630 postmarketOS port");
MODULE_DESCRIPTION("RMX3630 BQ25890H 80 percent charge limit");
MODULE_LICENSE("GPL");
