package org.seplans.api;

import java.util.List;

/**
 * @param status  ok, unsupported (a family the rules do not cover yet), invalid or error
 * @param message explanation when status is not ok; with ok, an optional remark on the
 *                result (for instance that the estate has no heir)
 */
public record SuccessionResponse(String status, String message, List<HeirResult> heirs) {

	public static SuccessionResponse failure(String status, String message) {
		return new SuccessionResponse(status, message, List.of());
	}
}
