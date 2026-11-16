package org.seplans.api;

import java.math.BigDecimal;

/**
 * Outcome for one listed person. Amounts are in euros and null when they do not apply
 * (person is not an heir, or is exempt from tax).
 *
 * @param right     full, usufruct or bare (bare ownership)
 * @param fraction  fraction of the estate the right bears on, e.g. "3/8"
 * @param value     value of the share; for usufruct and bare ownership, the fiscal valuation
 * @param taxStatus exempt or computed
 * @param basis     the rule that gave or denied the share
 * @param taxBasis  the rule that set the tax
 */
public record HeirResult(String name, Relation relation, boolean heir, String right, String fraction,
		BigDecimal value, String taxStatus, BigDecimal allowance, BigDecimal taxable, BigDecimal tax,
		BigDecimal net, String basis, String taxBasis) {
}
