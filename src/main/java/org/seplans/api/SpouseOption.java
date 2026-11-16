package org.seplans.api;

/** The surviving spouse's choice when all children are common (Code civil art. 757). */
public enum SpouseOption {
	USUFRUCT, QUARTER;

	public String atom() {
		return name().toLowerCase();
	}
}
