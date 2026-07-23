// SPDX-License-Identifier: GPL-2.0
/* One-boot diagnostic for extracting the stock kernel's symbol CRCs. */

#include <linux/compiler.h>
#include <linux/export.h>
#include <linux/init.h>
#include <linux/module.h>
#include <linux/types.h>

/* Addresses from this boot's /proc/kallsyms (KASLR changes them on reboot). */
#define KSYMTAB_START      0xffffffd62d8dbfc0ULL
#define KSYMTAB_STOP       0xffffffd62d8edc78ULL
#define KCRCTAB_START      0xffffffd62d906668ULL
#define KSYMTAB_GPL_START  0xffffffd62d8edc78ULL
#define KSYMTAB_GPL_STOP   0xffffffd62d906668ULL
#define KCRCTAB_GPL_START  0xffffffd62d90c550ULL

static char *symbols;
module_param(symbols, charp, 0400);
MODULE_PARM_DESC(symbols, "Comma-separated exported symbol names to dump");

static bool name_is_wanted(const char *name)
{
	const char *entry = symbols;

	if (!entry || !*entry)
		return false;

	while (*entry) {
		const char *candidate = entry;
		const char *actual = name;

		while (*candidate && *candidate != ',' &&
		       *actual && *candidate == *actual) {
			candidate++;
			actual++;
		}

		if (!*actual && (!*candidate || *candidate == ','))
			return true;

		while (*entry && *entry != ',')
			entry++;
		if (*entry == ',')
			entry++;
	}

	return false;
}

static void dump_table(unsigned long symbols_start,
		       unsigned long symbols_stop,
		       unsigned long crcs_start)
{
	const struct kernel_symbol *symbol = (const void *)symbols_start;
	const struct kernel_symbol *end = (const void *)symbols_stop;
	const u32 *crc = (const void *)crcs_start;

	for (; symbol < end; symbol++, crc++) {
		const char *name = offset_to_ptr(&symbol->name_offset);

		if (name_is_wanted(name))
			pr_info("RMXCRC %s 0x%08x\n", name, *crc);
	}
}

static int __init rmx3630_dump_crcs_init(void)
{
	pr_info("RMXCRC BEGIN\n");
	dump_table(KSYMTAB_START, KSYMTAB_STOP, KCRCTAB_START);
	dump_table(KSYMTAB_GPL_START, KSYMTAB_GPL_STOP,
		   KCRCTAB_GPL_START);
	pr_info("RMXCRC END\n");

	/* A failed init unloads the diagnostic so it can be run again. */
	return -EINVAL;
}
module_init(rmx3630_dump_crcs_init);

MODULE_DESCRIPTION("RMX3630 stock-kernel modversion CRC dumper");
MODULE_AUTHOR("RMX3630 postmarketOS port");
MODULE_LICENSE("GPL");
