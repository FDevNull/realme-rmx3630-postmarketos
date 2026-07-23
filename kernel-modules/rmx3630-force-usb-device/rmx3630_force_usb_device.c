// SPDX-License-Identifier: GPL-2.0
#include <linux/err.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/of_platform.h>
#include <linux/usb/role.h>

static int force_stage;
static int force_result = -EINPROGRESS;

module_param_named(stage, force_stage, int, 0444);
MODULE_PARM_DESC(stage, "Last completed initialization stage");
module_param_named(result, force_result, int, 0444);
MODULE_PARM_DESC(result, "Result returned by usb_role_switch_set_role");

/*
 * RMX3630's downstream MUSB driver registers a normal usb_role_switch, but it
 * deliberately hides the writable sysfs "role" attribute.  Android's extcon
 * driver reaches the same switch through the extcon_usb DT graph, then drags
 * in a large charger stack just to report that the cable is present.  Bind to
 * that consumer node directly and request peripheral mode without the charger
 * stack.
 */
static int __init rmx3630_force_usb_device_init(void)
{
	struct device_node *node;
	struct platform_device *pdev;
	struct usb_role_switch *role_sw;
	int ret;

	node = of_find_compatible_node(NULL, NULL, "mediatek,extcon-usb");
	if (!node) {
		force_result = -ENODEV;
		return 0;
	}
	force_stage = 1;

	pdev = of_find_device_by_node(node);
	if (!pdev) {
		force_result = -EPROBE_DEFER;
		return 0;
	}
	force_stage = 2;

	role_sw = usb_role_switch_get(&pdev->dev);
	if (IS_ERR(role_sw)) {
		force_result = PTR_ERR(role_sw);
		return 0;
	}
	if (!role_sw) {
		force_result = -EPROBE_DEFER;
		return 0;
	}
	force_stage = 3;

	ret = usb_role_switch_set_role(role_sw, USB_ROLE_DEVICE);
	force_result = ret;
	force_stage = 4;

	dev_info(&pdev->dev, "force device role result=%d\n", force_result);
	return 0;
}
module_init(rmx3630_force_usb_device_init);

MODULE_AUTHOR("RMX3630 postmarketOS port");
MODULE_DESCRIPTION("Force the RMX3630 downstream MUSB role switch to peripheral mode");
MODULE_LICENSE("GPL");
