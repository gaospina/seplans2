package org.seplans.api;

/**
 * A living relative of the deceased.
 *
 * @param commonChild for a child: whether the surviving spouse is also this child's parent
 */
public record PersonInput(String name, Relation relation, Boolean commonChild) {

	/** A child counts as common only when explicitly flagged. */
	public boolean isCommonChild() {
		return relation == Relation.CHILD && Boolean.TRUE.equals(commonChild);
	}
}
