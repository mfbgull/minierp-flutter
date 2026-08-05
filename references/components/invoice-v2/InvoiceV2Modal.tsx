import { useState, useEffect, useRef, useCallback, type ReactNode } from 'react';
import type { InvoiceV2ModalProps } from '../../types/invoiceV2';
import '../../styles/pages/invoice-v2.css';

interface InvoiceV2ModalShellProps extends InvoiceV2ModalProps {
  /** Whether the form has unsaved changes */
  isDirty: boolean;
  /** Modal content */
  children: ReactNode;
}

/**
 * InvoiceV2Modal — The outer modal shell for the invoice creation dialog.
 *
 * Responsibilities:
 * - Overlay backdrop with click-to-close (with dirty check)
 * - Escape key handler with dirty check
 * - Body scroll lock
 * - Enter/exit animations
 * - Focus trap (Tab cycles within the modal)
 * - Discard confirmation dialog
 * - ARIA attributes
 */
export default function InvoiceV2Modal({
  isOpen,
  onClose,
  isDirty,
  children,
}: InvoiceV2ModalShellProps) {
  const [showExitConfirm, setShowExitConfirm] = useState(false);
  const [exiting, setExiting] = useState(false);
  const modalRef = useRef<HTMLDivElement>(null);
  const previousFocusRef = useRef<HTMLElement | null>(null);

  /* ── Close handler with dirty check ─────────────────────────── */

  const handleClose = useCallback(() => {
    if (isDirty) {
      setShowExitConfirm(true);
    } else {
      doClose();
    }
  }, [isDirty]);

  const doClose = useCallback(() => {
    setExiting(true);
    setTimeout(() => {
      setExiting(false);
      onClose();
    }, 150);
  }, [onClose]);

  /* ── Escape key ────────────────────────────────────────────── */

  useEffect(() => {
    if (!isOpen) return;

    const handleEscape = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.preventDefault();
        handleClose();
      }
    };

    document.addEventListener('keydown', handleEscape);
    return () => document.removeEventListener('keydown', handleEscape);
  }, [isOpen, handleClose]);

  /* ── Body scroll lock ──────────────────────────────────────── */

  useEffect(() => {
    if (isOpen) {
      previousFocusRef.current = document.activeElement as HTMLElement;
      document.body.style.overflow = 'hidden';
    } else {
      document.body.style.overflow = '';
      previousFocusRef.current?.focus();
    }

    return () => {
      document.body.style.overflow = '';
    };
  }, [isOpen]);

  /* ── Auto-focus on open ────────────────────────────────────── */

  useEffect(() => {
    if (isOpen && modalRef.current) {
      // Focus the first focusable element inside the modal
      const firstFocusable = modalRef.current.querySelector<HTMLElement>(
        'input, select, textarea, button, [tabindex]:not([tabindex="-1"])'
      );
      setTimeout(() => {
        firstFocusable?.focus();
      }, 50);
    }
  }, [isOpen]);

  /* ── Focus trap ────────────────────────────────────────────── */

  useEffect(() => {
    if (!isOpen) return;

    const modal = modalRef.current;
    if (!modal) return;

    const handleTabTrap = (e: KeyboardEvent) => {
      if (e.key !== 'Tab') return;

      const focusableElements = modal.querySelectorAll<HTMLElement>(
        'input, select, textarea, button, [tabindex]:not([tabindex="-1"])'
      );
      const firstEl = focusableElements[0];
      const lastEl = focusableElements[focusableElements.length - 1];

      if (e.shiftKey) {
        if (document.activeElement === firstEl) {
          e.preventDefault();
          lastEl?.focus();
        }
      } else {
        if (document.activeElement === lastEl) {
          e.preventDefault();
          firstEl?.focus();
        }
      }
    };

    document.addEventListener('keydown', handleTabTrap);
    return () => document.removeEventListener('keydown', handleTabTrap);
  }, [isOpen]);

  /* ── Render nothing when closed ────────────────────────────── */

  if (!isOpen) return null;

  return (
    <>
      {/* Overlay backdrop */}
      <div
        className="iv2-overlay"
        onClick={(e) => {
          if (e.target === e.currentTarget) handleClose();
        }}
        role="dialog"
        aria-modal="true"
        aria-label="Create Invoice"
      >
        <div
          ref={modalRef}
          className={`iv2-modal${exiting ? ' iv2-modal-exit' : ''}`}
          onClick={(e) => e.stopPropagation()}
        >
          {children}
        </div>
      </div>

      {/* Discard confirmation dialog */}
      {showExitConfirm && (
        <div
          className="iv2-confirm-overlay"
          onClick={() => setShowExitConfirm(false)}
        >
          <div
            className="iv2-confirm-dialog"
            onClick={(e) => e.stopPropagation()}
          >
            <h3>Discard Invoice?</h3>
            <p>You have unsaved changes. Are you sure you want to exit?</p>
            <div className="iv2-confirm-actions">
              <button
                className="iv2-btn"
                onClick={() => setShowExitConfirm(false)}
                type="button"
              >
                Continue Editing
              </button>
              <button
                className="iv2-btn primary"
                onClick={() => {
                  setShowExitConfirm(false);
                  doClose();
                }}
                type="button"
                style={{ background: '#ef4444', borderColor: '#ef4444' }}
              >
                Discard
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  );
}
