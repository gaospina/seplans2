package org.seplans.api;

/**
 * A relative of the deceased.
 *
 * @param alive            false if the person died before the deceased; absent means alive.
 *                         Predeceased children and siblings are listed so that their
 *                         descendants can represent them.
 * @param via              for {@link Relation#DESCENDANT} and {@link Relation#SIBLING_DESCENDANT}:
 *                         position in the list (from 0) of this person's parent
 * @param line             for ordinary ascendants and collaterals: the father's or mother's side
 * @param commonChild      for a child: whether the surviving spouse is also this child's parent
 * @param disabled         entitled to the disability allowance (CGI art. 779 II)
 * @param siblingExemption for a sibling: meets the exemption conditions of CGI art. 796-0 ter
 */
public record PersonInput(String name, Relation relation, Boolean alive, Integer via, Line line,
		Boolean commonChild, Boolean disabled, Boolean siblingExemption) {

	public boolean isPredeceased() {
		return Boolean.FALSE.equals(alive);
	}

	/** A child counts as common only when explicitly flagged. */
	public boolean isCommonChild() {
		return relation == Relation.CHILD && Boolean.TRUE.equals(commonChild);
	}

	public boolean isDisabled() {
		return Boolean.TRUE.equals(disabled);
	}

	public boolean isExemptSibling() {
		return relation == Relation.SIBLING && Boolean.TRUE.equals(siblingExemption);
	}
}
