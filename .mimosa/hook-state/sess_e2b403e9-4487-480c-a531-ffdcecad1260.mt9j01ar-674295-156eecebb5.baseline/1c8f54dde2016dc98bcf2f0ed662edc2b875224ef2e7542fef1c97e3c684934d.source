import { useState, useEffect, useCallback } from 'react';
import { Keyboard, X } from 'lucide-react';

interface Shortcut {
  keys: string[];
  description: string;
  section: string;
}

const shortcuts: Shortcut[] = [
  // Navigation
  { keys: ['↑', '↓'], description: 'Navigate between rows', section: 'Navigation' },
  { keys: ['←', '→'], description: 'Navigate between fields', section: 'Navigation' },
  { keys: ['Tab'], description: 'Move to next field', section: 'Navigation' },
  { keys: ['Shift', 'Tab'], description: 'Move to previous field', section: 'Navigation' },

  // Editing
  { keys: ['Enter'], description: 'Select item / Add new row (at last row)', section: 'Editing' },
  { keys: ['Escape'], description: 'Cancel editing / Close dropdown', section: 'Editing' },
  { keys: ['Ctrl', '↑'], description: 'Increment value by 1', section: 'Editing' },
  { keys: ['Ctrl', '↓'], description: 'Decrement value by 1', section: 'Editing' },

  // Global
  { keys: ['Alt', 'I'], description: 'Add new line item', section: 'Global' },
  { keys: ['Alt', 'C'], description: 'Focus customer field', section: 'Global' },
  { keys: ['Ctrl', 'S'], description: 'Save invoice', section: 'Global' },
  { keys: ['Shift', 'Enter'], description: 'Focus payment section', section: 'Global' },
];

export default function KeyboardShortcutsHelp() {
  const [isOpen, setIsOpen] = useState(false);

  const toggle = useCallback(() => setIsOpen((prev) => !prev), []);

  // Close on Escape
  useEffect(() => {
    if (!isOpen) return;
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.preventDefault();
        setIsOpen(false);
      }
    };
    document.addEventListener('keydown', handleKeyDown);
    return () => document.removeEventListener('keydown', handleKeyDown);
  }, [isOpen]);

  // Group shortcuts by section
  const sections = shortcuts.reduce<Record<string, Shortcut[]>>((acc, shortcut) => {
    if (!acc[shortcut.section]) acc[shortcut.section] = [];
    acc[shortcut.section].push(shortcut);
    return acc;
  }, {});

  return (
    <>
      {/* Toggle Button */}
      <button
        type="button"
        onClick={toggle}
        className="keyboard-shortcuts-toggle"
        title="Keyboard Shortcuts"
        aria-label="Show keyboard shortcuts"
        aria-expanded={isOpen}
      >
        <Keyboard size={16} />
      </button>

      {/* Panel */}
      {isOpen && (
        <div className="keyboard-shortcuts-backdrop" onClick={() => setIsOpen(false)}>
          <div
            className="keyboard-shortcuts-panel"
            onClick={(e) => e.stopPropagation()}
            role="dialog"
            aria-label="Keyboard shortcuts"
          >
            <div className="keyboard-shortcuts-header">
              <h3>
                <Keyboard size={18} />
                Keyboard Shortcuts
              </h3>
              <button
                type="button"
                onClick={() => setIsOpen(false)}
                className="keyboard-shortcuts-close"
                aria-label="Close"
              >
                <X size={16} />
              </button>
            </div>

            <div className="keyboard-shortcuts-body">
              {Object.entries(sections).map(([section, items]) => (
                <div key={section} className="keyboard-shortcuts-section">
                  <h4 className="keyboard-shortcuts-section-title">{section}</h4>
                  <div className="keyboard-shortcuts-list">
                    {items.map((shortcut, idx) => (
                      <div key={idx} className="keyboard-shortcuts-item">
                        <div className="keyboard-shortcuts-keys">
                          {shortcut.keys.map((key, kIdx) => (
                            <span key={kIdx}>
                              <kbd className="keyboard-shortcuts-key">{key}</kbd>
                              {kIdx < shortcut.keys.length - 1 && (
                                <span className="keyboard-shortcuts-separator">+</span>
                              )}
                            </span>
                          ))}
                        </div>
                        <span className="keyboard-shortcuts-description">
                          {shortcut.description}
                        </span>
                      </div>
                    ))}
                  </div>
                </div>
              ))}
            </div>

            <div className="keyboard-shortcuts-footer">
              Press <kbd>Esc</kbd> to close
            </div>
          </div>
        </div>
      )}
    </>
  );
}
