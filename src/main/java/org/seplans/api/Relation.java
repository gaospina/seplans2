package org.seplans.api;

/** Relationship of a listed person to the deceased. */
public enum Relation {
	SPOUSE,
	PACS_PARTNER,
	COHABITANT,
	CHILD,
	/** Grandchild or further descendant, linked to their parent by {@code via}. */
	DESCENDANT,
	FATHER,
	MOTHER,
	SIBLING,
	/** Nephew, niece or their descendant, linked to their parent by {@code via}. */
	SIBLING_DESCENDANT,
	GRANDPARENT,
	GREAT_GRANDPARENT,
	UNCLE_AUNT,
	GREAT_UNCLE_AUNT,
	FIRST_COUSIN,
	/** Any other collateral of the fifth degree. */
	COLLATERAL_5,
	/** Any other collateral of the sixth degree. */
	COLLATERAL_6;

	/** The atom used for this relation in the Prolog rule base. */
	public String atom() {
		return name().toLowerCase();
	}

	/** Whether the person is related through a listed parent ({@code via}). */
	public boolean linkedByParent() {
		return this == DESCENDANT || this == SIBLING_DESCENDANT;
	}

	/** Whether the paternal or maternal line matters for this relation. */
	public boolean needsLine() {
		return switch (this) {
			case GRANDPARENT, GREAT_GRANDPARENT, UNCLE_AUNT, GREAT_UNCLE_AUNT, FIRST_COUSIN, COLLATERAL_5,
					COLLATERAL_6 -> true;
			default -> false;
		};
	}
}
