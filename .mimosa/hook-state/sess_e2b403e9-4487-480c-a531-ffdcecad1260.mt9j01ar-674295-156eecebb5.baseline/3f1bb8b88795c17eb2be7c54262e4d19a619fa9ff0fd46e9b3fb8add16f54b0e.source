export function shouldIgnoreShortcut(event: KeyboardEvent): boolean {
  const activeElement = document.activeElement;
  
  if (activeElement && (
    activeElement.tagName === 'INPUT' ||
    activeElement.tagName === 'TEXTAREA' ||
    activeElement.getAttribute('contenteditable') === 'true'
  )) {
    if (event.ctrlKey || event.metaKey) {
      if (event.key === 's') {
        return false;
      }
    }
    return true;
  }
  
  if (activeElement && activeElement.classList.contains('ag-cell-edit-handle')) {
    return true;
  }
  
  return false;
}
