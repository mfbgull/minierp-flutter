import { useRef, useCallback } from 'react';

/**
 * Shared hook for cell-to-cell keyboard navigation with timing fixes.
 *
 * Provides a `focusTargetCell` callback that:
 * 1. Uses setTimeout(0) + requestAnimationFrame to let React commit edit-mode render
 * 2. Includes a navigation cancellation token to discard stale timeouts on rapid keypresses
 * 3. Guards against focus loss when the target cell disappears mid-navigation
 * 4. Focuses the input (selecting text) when available, otherwise the cell element
 *
 * Also exposes `isNavigatingRef` so callers can suppress onBlur race conditions.
 */
export function useFocusCell(onEditingCell: (cellId: string | null) => void) {
  // Navigation cancellation token — incremented on each navigation so stale timeouts are discarded
  const navigationIdRef = useRef(0);
  // Flag to suppress onBlur when keyboard navigation is in progress
  const isNavigatingRef = useRef(false);

  const focusTargetCell = useCallback(
    (targetItemId: number, targetField: string) => {
      isNavigatingRef.current = true;
      const navId = ++navigationIdRef.current;
      // Call onEditingCell synchronously so React starts the edit-mode render
      onEditingCell(`${targetItemId}-${targetField}`);
      // Double rAF: first rAF fires after React commits state, second after DOM paint
      requestAnimationFrame(() => {
        if (navId !== navigationIdRef.current) return; // stale
        requestAnimationFrame(() => {
          if (navId !== navigationIdRef.current) return; // stale
          const el = document.querySelector(
            `[data-cell-id="${targetItemId}-${targetField}"]`,
          );
          if (!el) {
            isNavigatingRef.current = false;
            return;
          }
          const input = el.querySelector('input');
          if (input) {
            (input as HTMLInputElement).focus();
            (input as HTMLInputElement).select();
          } else {
            (el as HTMLElement).focus();
          }
          isNavigatingRef.current = false;
        });
      });
    },
    [onEditingCell],
  );

  return { focusTargetCell, isNavigatingRef } as const;
}
