package org.seplans.api;

import java.math.BigDecimal;
import java.util.List;

/**
 * Outcome for one listed person. Amounts are in euros and null when they do not apply
 * (person is not an heir, or is exempt from tax).
 *
 * @param right          full, usufruct or bare (bare ownership)
 * @param fraction       fraction of the estate the right bears on, e.g. "3/8"
 * @param value          value of the share; for usufruct and bare ownership, the fiscal valuation
 * @param taxStatus      exempt or computed
 * @param allowance      allowance applied: the sum of {@code allowanceParts}, capped at the value
 * @param basis          the rule that gave or denied the share
 * @param taxBasis       the rule that set the tax
 * @param allowanceParts the allowances the heir is entitled to
 * @param brackets       the tax, bracket by bracket
 */
public record HeirResult(String name, Relation relation, boolean heir, String right, String fraction,
		BigDecimal value, String taxStatus, BigDecimal allowance, BigDecimal taxable, BigDecimal tax,
		BigDecimal net, String basis, String taxBasis, List<AllowancePart> allowanceParts,
		List<Bracket> brackets) {

	public record AllowancePart(String label, BigDecimal amount) {
	}

	/**
	 * @param from lower bound of the slice of the taxable amount
	 * @param to   upper bound of the slice
	 * @param rate rate in percent
	 * @param tax  tax on the slice
	 */
	public record Bracket(BigDecimal from, BigDecimal to, int rate, BigDecimal tax) {
	}
}
