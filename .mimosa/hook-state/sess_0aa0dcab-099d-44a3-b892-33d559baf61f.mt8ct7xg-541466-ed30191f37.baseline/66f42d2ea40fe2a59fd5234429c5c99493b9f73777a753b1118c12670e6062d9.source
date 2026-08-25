import { useState, useRef, useEffect } from 'react';
import { Type } from 'lucide-react';
import type { DashboardBlockComponentProps } from './BlockComponentProps';

export default function CustomTextBlock({ config, isEditing, onConfigChange }: DashboardBlockComponentProps) {
  const text = (config.text as string) || 'Your heading or notes here';
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState(text);
  const textareaRef = useRef<HTMLTextAreaElement>(null);

  // If user exits edit mode while inline editing, close the textarea
  useEffect(() => {
    if (!isEditing) {
      setEditing(false);
      setDraft(text);
    }
  }, [isEditing, text]);

  const handleSave = () => {
    onConfigChange({ text: draft });
    setEditing(false);
  };

  const handleCancel = () => {
    setDraft(text);
    setEditing(false);
  };

  if (isEditing) {
    return (
      <div style={{ height: '100%', display: 'flex', flexDirection: 'column', gap: 8, padding: 4 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: '0.85rem', color: 'var(--neutral-500)' }}>
          <Type size={14} />
          <span>Double-click to edit text</span>
        </div>
        <div style={{ fontSize: '1.1rem', fontWeight: 600, color: 'var(--neutral-800)', padding: '4px 0' }}>
          {text}
        </div>
      </div>
    );
  }

  return (
    <div
      style={{ height: '100%', display: 'flex', flexDirection: 'column', justifyContent: 'center', padding: '8px 12px', cursor: 'default' }}
      onDoubleClick={() => {
        setDraft(text);
        setEditing(true);
        setTimeout(() => textareaRef.current?.focus(), 0);
      }}
    >
      {editing ? (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
          <textarea
            ref={textareaRef}
            value={draft}
            onChange={(e) => setDraft(e.target.value)}
            onBlur={handleSave}
            onKeyDown={(e) => {
              if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); handleSave(); }
              if (e.key === 'Escape') handleCancel();
            }}
            style={{
              width: '100%', minHeight: 60, padding: '8px 10px', border: '2px solid var(--primary)',
              borderRadius: 6, fontSize: '1rem', fontFamily: 'inherit', resize: 'vertical',
              background: 'white',
            }}
            autoFocus
          />
          <div style={{ display: 'flex', gap: 6, justifyContent: 'flex-end' }}>
            <button onClick={handleCancel} style={{ padding: '4px 12px', borderRadius: 4, border: '1px solid var(--neutral-300)', background: 'white', cursor: 'pointer', fontSize: '0.8rem' }}>
              Cancel
            </button>
            <button onClick={handleSave} style={{ padding: '4px 12px', borderRadius: 4, border: 'none', background: 'var(--primary)', color: 'white', cursor: 'pointer', fontSize: '0.8rem' }}>
              Save
            </button>
          </div>
        </div>
      ) : (
        <div style={{ fontSize: '1.1rem', fontWeight: 600, color: 'var(--neutral-800)', lineHeight: 1.5 }}>
          {text}
        </div>
      )}
    </div>
  );
}
