package org.seplans.api;

import java.util.List;

/**
 * @param status          ok, invalid or error
 * @param message         explanation when status is not ok; with ok, an optional remark on the
 *                        result (for instance that the estate has no heir)
 * @param warnings        things in the input that were accepted but deserve a second look
 * @param usufructPercent when the spouse takes the usufruct: its value as a percentage of
 *                        full ownership (CGI art. 669), otherwise null
 */
public record SuccessionResponse(String status, String message, List<HeirResult> heirs, List<String> warnings,
		Integer usufructPercent) {

	public static SuccessionResponse failure(String status, String message) {
		return new SuccessionResponse(status, message, List.of(), List.of(), null);
	}
}
