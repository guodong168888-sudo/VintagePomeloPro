export interface BottomNavigationLayout {
  barHeight: number;
  bottomMargin: number;
  sideMargin: number;
  containerHeight: number;
  contentInset: number;
}

/** One owner for floating bar geometry, gesture avoidance and list clearance. */
export function bottomNavigationLayout(landscape: boolean, safeBottom: number): BottomNavigationLayout {
  const barHeight = 56; // HDS floating-tab default; includes the framework's inner padding.
  const inset = Number.isFinite(safeBottom) ? Math.max(0, safeBottom) : 0;
  const bottomMargin = Math.max(landscape ? 10 : 14, inset);
  const containerHeight = barHeight + bottomMargin + 12; // Shadow/gradient space above the bar.
  return {
    barHeight: barHeight,
    bottomMargin: bottomMargin,
    sideMargin: landscape ? 24 : 20,
    containerHeight: containerHeight,
    contentInset: containerHeight + 8
  };
}
