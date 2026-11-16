package org.seplans.api;

/** The side of the deceased's family an ascendant or collateral belongs to. */
public enum Line {
	PATERNAL, MATERNAL;

	public String atom() {
		return name().toLowerCase();
	}
}
