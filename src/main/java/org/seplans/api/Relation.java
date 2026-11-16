package org.seplans.api;

/** Relationship of a listed person to the deceased. */
public enum Relation {
	SPOUSE, CHILD, FATHER, MOTHER;

	/** The atom used for this relation in the Prolog rule base. */
	public String atom() {
		return name().toLowerCase();
	}
}
