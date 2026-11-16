package org.seplans.api;

import java.math.BigDecimal;
import java.util.List;

/**
 * One succession to solve.
 *
 * @param estate       net estate in euros
 * @param spouseAge    age of the surviving spouse, needed to value a usufruct
 * @param spouseOption the spouse's choice when all children are common
 */
public record SuccessionRequest(BigDecimal estate, List<PersonInput> persons, Integer spouseAge,
		SpouseOption spouseOption) {
}
