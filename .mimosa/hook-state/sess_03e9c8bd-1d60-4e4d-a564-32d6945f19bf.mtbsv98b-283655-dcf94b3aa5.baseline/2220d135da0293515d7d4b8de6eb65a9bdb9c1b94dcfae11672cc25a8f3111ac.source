/**
 * useDashboardLayout — Core state hook for the dashboard customization system.
 *
 * Responsibilities:
 * - Load layout from server with localStorage cache for instant first paint
 * - Manage block positions, sizes, and config in local state
 * - Undo/redo stack (max 50 actions)
 * - Auto-save with 1s debounce + error handling (retry once after 3s)
 * - Save-state indicator (saved / unsaved / saving / saveFailed)
 * - localStorage cache with updated_at timestamp reconciliation
 * - Browser tab sync via storage event
 * - Default layout fallback when no saved layout exists
 *
 * @see dashboard-customization-spec.md §3 — Edit Mode
 * @see dashboard-customization-spec.md §6 — Frontend Architecture
 */

import { useState, useCallback, useRef, useEffect } from 'react';
import toast from 'react-hot-toast';
import api from '../utils/api';
import { getBlockEntry, type DashboardBlockType, DEFAULT_LAYOUT_BLOCKS } from '../utils/dashboardBlockRegistry';

// ═══════════════════════════════════════════════════════════════
//  TYPES
// ═══════════════════════════════════════════════════════════════

export interface DashboardBlockConfig {
  refreshInterval?: number;
  text?: string;
  metric?: string;
  limit?: number;
  period?: string;
  days?: number;
  [key: string]: unknown;
}

export interface DashboardBlock {
  id: string;
  type: DashboardBlockType | string;
  title: string;
  x: number;
  y: number;
  width: number;
  height: number;
  visible: boolean;
  version: number;
  config: DashboardBlockConfig;
}

export type BlocksArray = DashboardBlock[];

export interface DashboardLayout {
  id: number;
  user_id: number;
  layout_name: string;
  blocks: BlocksArray;
  is_active: boolean;
  created_at: string;
  updated_at: string;
}

export type SaveState = 'saved' | 'unsaved' | 'saving' | 'saveFailed';

interface DashboardEditAction {
  type: 'add' | 'remove' | 'move' | 'resize' | 'config_change';
  blockId: string;
  previous: Partial<DashboardBlock> | null;
  current: Partial<DashboardBlock> | null;
}

interface LayoutCache {
  layout: DashboardLayout;
  updated_at: string;
}

// ═══════════════════════════════════════════════════════════════
//  CONSTANTS
// ═══════════════════════════════════════════════════════════════

const STORAGE_KEY = 'dashboard-layout';
const MAX_UNDO_STACK = 50;
const AUTO_SAVE_DELAY_MS = 1000;
const AUTO_RETRY_DELAY_MS = 3000;
const MAX_AUTO_RETRIES = 1;
const MAX_BLOCKS = 20;
const GRID_COLUMNS = 3;

// ═══════════════════════════════════════════════════════════════
//  HELPERS
// ═══════════════════════════════════════════════════════════════

function generateId(): string {
  try {
    return crypto.randomUUID();
  } catch {
    // Fallback for older environments
    return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}-${Math.random().toString(36).slice(2, 10)}`;
  }
}

function blocksFromDefault(): BlocksArray {
  return DEFAULT_LAYOUT_BLOCKS.map((item) => {
    const entry = getBlockEntry(item.type);
    return {
      id: generateId(),
      type: item.type,
      title: '', // Will be filled from i18n at render time
      x: item.x,
      y: item.y,
      width: entry.defaultSize.width,
      height: entry.defaultSize.height,
      visible: true,
      version: 1,
      config: { ...entry.defaultConfig },
    };
  });
}

function createDefaultLayout(): DashboardLayout {
  return {
    id: 0,
    user_id: 0,
    layout_name: 'Default',
    blocks: blocksFromDefault(),
    is_active: true,
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
  };
}

function saveToLocalStorage(layout: DashboardLayout): void {
  try {
    const cache: LayoutCache = {
      layout,
      updated_at: layout.updated_at,
    };
    localStorage.setItem(STORAGE_KEY, JSON.stringify(cache));
  } catch {
    // localStorage quota exceeded or unavailable — silently ignore
  }
}

function loadFromLocalStorage(): DashboardLayout | null {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return null;
    const cache = JSON.parse(raw) as LayoutCache;
    if (!cache?.layout?.blocks) return null;
    return cache.layout;
  } catch {
    return null;
  }
}

function clearLocalStorageCache(): void {
  try {
    localStorage.removeItem(STORAGE_KEY);
  } catch {
    // silently ignore
  }
}

function getLowestY(blocks: BlocksArray): number {
  if (blocks.length === 0) return 0;
  return Math.max(...blocks.map((b) => b.y + b.height));
}

// ═══════════════════════════════════════════════════════════════
//  HOOK
// ═══════════════════════════════════════════════════════════════

export function useDashboardLayout() {
  // ——— Core State ———
  const [layout, setLayout] = useState<DashboardLayout>(() => {
    return loadFromLocalStorage() || createDefaultLayout();
  });
  const [layoutId, setLayoutId] = useState<number | null>(
    () => loadFromLocalStorage()?.id ?? null,
  );
  const [layoutName, setLayoutName] = useState<string>(
    () => loadFromLocalStorage()?.layout_name || 'Default',
  );
  const [isEditing, setIsEditing] = useState(false);
  const [saveState, setSaveState] = useState<SaveState>('saved');
  const [isLoading, setIsLoading] = useState(true);

  // ——— Undo / Redo ———
  const [undoStack, setUndoStack] = useState<DashboardEditAction[]>([]);
  const [redoStack, setRedoStack] = useState<DashboardEditAction[]>([]);

  // ——— Refs (to avoid stale closures in debounced callbacks) ———
  const layoutRef = useRef(layout);
  const layoutIdRef = useRef(layoutId);
  const saveStateRef = useRef(saveState);
  const autoSaveTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const retryTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const retryCountRef = useRef(0);
  const isMountedRef = useRef(true);
  /** Tracks the last-known-server-state blocks for dirty-state comparison */
  const lastSavedBlocksRef = useRef<DashboardBlock[]>(layout.blocks);

  // Keep refs in sync
  useEffect(() => { layoutRef.current = layout; }, [layout]);
  useEffect(() => { layoutIdRef.current = layoutId; }, [layoutId]);
  useEffect(() => { saveStateRef.current = saveState; }, [saveState]);

  useEffect(() => {
    return () => {
      isMountedRef.current = false;
      if (autoSaveTimerRef.current) clearTimeout(autoSaveTimerRef.current);
      if (retryTimerRef.current) clearTimeout(retryTimerRef.current);
    };
  }, []);

  // ═════════════════════════════════════════════════════════════
  //  LOAD LAYOUT FROM SERVER
  // ═════════════════════════════════════════════════════════════

  const fetchLayout = useCallback(async () => {
    setIsLoading(true);
    try {
      const response = await api.get<{ success: boolean; data: DashboardLayout | null }>(
        '/dashboard/layout/active',
      );

      if (response.data?.success && response.data.data) {
        const serverLayout = response.data.data;

        // Reconcile with localStorage: compare updated_at timestamps
        const cached = loadFromLocalStorage();
        const cachedTime = cached?.updated_at ? new Date(cached.updated_at).getTime() : 0;
        const serverTime = serverLayout.updated_at ? new Date(serverLayout.updated_at.replace(' ', 'T')).getTime() : 0;
        if (cached && cachedTime > serverTime) {
          // Local is newer — keep local, will push to server on next auto-save
          setLayout(cached);
          setLayoutId(cached.id);
          setLayoutName(cached.layout_name);
        } else {
          // Server is newer or they match — use server data
          setLayout(serverLayout);
          setLayoutId(serverLayout.id);
          setLayoutName(serverLayout.layout_name);
          saveToLocalStorage(serverLayout);
          lastSavedBlocksRef.current = serverLayout.blocks;
        }
      } else {
        // 404 — no active layout. Check for existing layouts on the server.
        const cached = loadFromLocalStorage();
        if (cached && cached.id > 0) {
          // Valid cached layout — use it (has real server id)
          setLayout(cached);
          setLayoutId(cached.id);
          setLayoutName(cached.layout_name);
        } else {
          // No cache, or cached layout has synthetic id (<=0)
          // Try to find the real layout from the server
          try {
            const listResp = await api.get<{ success: boolean; data: DashboardLayout[] }>('/dashboard/layouts');
            if (listResp.data?.success && listResp.data.data?.length > 0) {
              const existing = listResp.data.data[0];
              setLayout(existing);
              setLayoutId(existing.id);
              setLayoutName(existing.layout_name);
              saveToLocalStorage(existing);
              lastSavedBlocksRef.current = existing.blocks;
            } else if (cached) {
              // Server has no layouts either — keep cached as fallback
              setLayout(cached);
              setLayoutId(cached.id);
              setLayoutName(cached.layout_name);
            }
          } catch {
            // Network error — keep the cached layout
            if (cached) {
              setLayout(cached);
              setLayoutId(cached.id);
              setLayoutName(cached.layout_name);
            }
          }
        }
      }
    } catch (err: unknown) {
      // 404 (no active layout) hits here because Axios throws on non-2xx.
      // Also catches true network errors.
      console.log('[fetchLayout] CATCH block entered', (err as any)?.response?.status || 'no status');
      const cached = loadFromLocalStorage();
      console.log('[fetchLayout] cached from localStorage:', cached);
      if (cached && cached.id > 0) {
        // Valid cached layout — use it
        setLayout(cached);
        setLayoutId(cached.id);
        setLayoutName(cached.layout_name);
      } else {
        // No cache, or cached layout has synthetic id (<=0)
        // Try to find the real layout from the server
        console.log('[fetchLayout] cache missing/synthetic, trying GET /layouts');
        try {
          const listResp = await api.get<{ success: boolean; data: DashboardLayout[] }>('/dashboard/layouts');
          if (listResp.data?.success && listResp.data.data?.length > 0) {
            const existing = listResp.data.data[0];
            setLayout(existing);
            setLayoutId(existing.id);
            setLayoutName(existing.layout_name);
            saveToLocalStorage(existing);
          } else if (cached) {
            // Server has no layouts either — keep cached as fallback
            setLayout(cached);
            setLayoutId(cached.id);
            setLayoutName(cached.layout_name);
          }
        } catch {
          // Network error — keep the cached layout
          if (cached) {
            setLayout(cached);
            setLayoutId(cached.id);
            setLayoutName(cached.layout_name);
          }
        }
      }
    } finally {
      setIsLoading(false);
    }
  }, []);

  // Fetch layout on mount
  useEffect(() => {
    fetchLayout();
  }, [fetchLayout]);

  // ═════════════════════════════════════════════════════════════
  //  TAB SYNC
  // ═════════════════════════════════════════════════════════════

  useEffect(() => {
    function handleStorageChange(e: StorageEvent) {
      if (e.key !== STORAGE_KEY) return;
      if (!isEditing) {
        // Only re-fetch if not currently editing (avoids overwriting edits)
        fetchLayout();
      }
    }

    window.addEventListener('storage', handleStorageChange);
    return () => window.removeEventListener('storage', handleStorageChange);
  }, [fetchLayout, isEditing]);

  // ═════════════════════════════════════════════════════════════
  //  UNDO / REDO HELPERS
  // ═════════════════════════════════════════════════════════════

  const pushUndo = useCallback((action: DashboardEditAction) => {
    setUndoStack((prev) => {
      const next = [...prev, action];
      if (next.length > MAX_UNDO_STACK) next.shift();
      return next;
    });
    setRedoStack([]); // Clear redo on new action
  }, []);

  // ═════════════════════════════════════════════════════════════
  //  BLOCK MUTATIONS (immutable updates + push undo)
  // ═════════════════════════════════════════════════════════════

  const addBlock = useCallback((type: DashboardBlockType | string) => {
    setLayout((prev) => {
      if (prev.blocks.length >= MAX_BLOCKS) return prev;

      const entry = getBlockEntry(type);
      const newBlock: DashboardBlock = {
        id: generateId(),
        type,
        title: '',
        x: 0,
        y: getLowestY(prev.blocks),
        width: entry.defaultSize.width,
        height: entry.defaultSize.height,
        visible: true,
        version: 1,
        config: { ...entry.defaultConfig },
      };

      const newBlocks = [...prev.blocks, newBlock];

      pushUndo({
        type: 'add',
        blockId: newBlock.id,
        previous: null,
        current: { id: newBlock.id, type, x: newBlock.x, y: newBlock.y },
      });

      const updated: DashboardLayout = {
        ...prev,
        blocks: newBlocks,
        updated_at: new Date().toISOString(),
      };

      setSaveState('unsaved');
      scheduleAutoSave(updated);
      return updated;
    });

    toast.success('Block added to dashboard');
  }, [pushUndo]);

  const removeBlock = useCallback((blockId: string) => {
    // Capture block info before the updater for the toast
    let removedTitle = '';
    const found = layoutRef.current.blocks.find((b) => b.id === blockId);
    if (found) removedTitle = found.title;

    setLayout((prev) => {
      const block = prev.blocks.find((b) => b.id === blockId);
      if (!block) return prev;

      const newBlocks = prev.blocks.filter((b) => b.id !== blockId);

      pushUndo({
        type: 'remove',
        blockId,
        previous: { ...block },
        current: null,
      });

      const updated: DashboardLayout = {
        ...prev,
        blocks: newBlocks,
        updated_at: new Date().toISOString(),
      };

      setSaveState('unsaved');
      scheduleAutoSave(updated);
      return updated;
    });

    toast.success(removedTitle ? `"${removedTitle}" removed` : 'Block removed from dashboard');
  }, [pushUndo]);

  const moveBlock = useCallback((blockId: string, x: number, y: number) => {
    setLayout((prev) => {
      const block = prev.blocks.find((b) => b.id === blockId);
      if (!block) return prev;
      if (block.x === x && block.y === y) return prev;

      const newBlocks = prev.blocks.map((b) =>
        b.id === blockId ? { ...b, x, y } : b,
      );

      pushUndo({
        type: 'move',
        blockId,
        previous: { x: block.x, y: block.y },
        current: { x, y },
      });

      const updated: DashboardLayout = {
        ...prev,
        blocks: newBlocks,
        updated_at: new Date().toISOString(),
      };

      setSaveState('unsaved');
      saveToLocalStorage(updated);
      scheduleAutoSave(updated);
      return updated;
    });
  }, [pushUndo]);

  const resizeBlock = useCallback((blockId: string, width: number, height: number) => {
    setLayout((prev) => {
      const block = prev.blocks.find((b) => b.id === blockId);
      if (!block) return prev;
      if (block.width === width && block.height === height) return prev;

      const newBlocks = prev.blocks.map((b) =>
        b.id === blockId ? { ...b, width, height } : b,
      );

      pushUndo({
        type: 'resize',
        blockId,
        previous: { width: block.width, height: block.height },
        current: { width, height },
      });

      const updated: DashboardLayout = {
        ...prev,
        blocks: newBlocks,
        updated_at: new Date().toISOString(),
      };

      setSaveState('unsaved');
      saveToLocalStorage(updated);
      scheduleAutoSave(updated);
      return updated;
    });
  }, [pushUndo]);

  const updateBlockConfig = useCallback(
    (blockId: string, config: Partial<DashboardBlockConfig>) => {
      setLayout((prev) => {
        const block = prev.blocks.find((b) => b.id === blockId);
        if (!block) return prev;

        const newBlocks = prev.blocks.map((b) =>
          b.id === blockId
            ? { ...b, config: { ...b.config, ...config } }
            : b,
        );

        pushUndo({
          type: 'config_change',
          blockId,
          previous: { config: { ...block.config } },
          current: { config: { ...block.config, ...config } },
        });

        const updated: DashboardLayout = {
          ...prev,
          blocks: newBlocks,
          updated_at: new Date().toISOString(),
        };

        setSaveState('unsaved');
        saveToLocalStorage(updated);
        scheduleAutoSave(updated);
        return updated;
      });
    },
    [pushUndo],
  );

  const updateBlockTitle = useCallback((blockId: string, title: string) => {
    setLayout((prev) => {
      const newBlocks = prev.blocks.map((b) =>
        b.id === blockId ? { ...b, title } : b,
      );

      const updated: DashboardLayout = {
        ...prev,
        blocks: newBlocks,
        updated_at: new Date().toISOString(),
      };

      setSaveState('unsaved');
      saveToLocalStorage(updated);
      scheduleAutoSave(updated);
      return updated;
    });
  }, []);

  // ═════════════════════════════════════════════════════════════
  //  UNDO / REDO
  // ═════════════════════════════════════════════════════════════

  const actionTypeLabels: Record<string, string> = {
    add: 'add block',
    remove: 'remove block',
    move: 'move block',
    resize: 'resize block',
    config_change: 'config change',
  };

  const undo = useCallback(() => {
    if (undoStack.length === 0) return;
    const action = undoStack[undoStack.length - 1];

    toast.success(`Undid: ${actionTypeLabels[action.type] || action.type}`);

    setUndoStack((prevUndo) => {
      setRedoStack((prevRedo) => [...prevRedo, action]);

      setLayout((prev) => {
        let newBlocks = [...prev.blocks];

        switch (action.type) {
          case 'add': {
            newBlocks = newBlocks.filter((b) => b.id !== action.blockId);
            break;
          }
          case 'remove': {
            if (action.previous) {
              newBlocks = [...newBlocks, action.previous as DashboardBlock];
            }
            break;
          }
          case 'move': {
            newBlocks = newBlocks.map((b) =>
              b.id === action.blockId
                ? { ...b, x: (action.previous?.x ?? b.x), y: (action.previous?.y ?? b.y) }
                : b,
            );
            break;
          }
          case 'resize': {
            newBlocks = newBlocks.map((b) =>
              b.id === action.blockId
                ? { ...b, width: (action.previous?.width ?? b.width), height: (action.previous?.height ?? b.height) }
                : b,
            );
            break;
          }
          case 'config_change': {
            newBlocks = newBlocks.map((b) =>
              b.id === action.blockId
                ? { ...b, config: (action.previous?.config as DashboardBlockConfig) || b.config }
                : b,
            );
            break;
          }
        }

        return {
          ...prev,
          blocks: newBlocks,
          updated_at: new Date().toISOString(),
        };
      });

      setSaveState('unsaved');
      return prevUndo.slice(0, -1);
    });
  }, [undoStack]);

  const redo = useCallback(() => {
    if (redoStack.length === 0) return;
    const action = redoStack[redoStack.length - 1];

    toast.success(`Redid: ${actionTypeLabels[action.type] || action.type}`);

    setRedoStack((prevRedo) => {
      setUndoStack((prevUndo) => [...prevUndo, action]);

      setLayout((prev) => {
        let newBlocks = [...prev.blocks];

        switch (action.type) {
          case 'add': {
            if (action.current) {
              newBlocks = [...newBlocks, action.current as DashboardBlock];
            }
            break;
          }
          case 'remove': {
            newBlocks = newBlocks.filter((b) => b.id !== action.blockId);
            break;
          }
          case 'move': {
            newBlocks = newBlocks.map((b) =>
              b.id === action.blockId
                ? { ...b, x: (action.current?.x ?? b.x), y: (action.current?.y ?? b.y) }
                : b,
            );
            break;
          }
          case 'resize': {
            newBlocks = newBlocks.map((b) =>
              b.id === action.blockId
                ? { ...b, width: (action.current?.width ?? b.width), height: (action.current?.height ?? b.height) }
                : b,
            );
            break;
          }
          case 'config_change': {
            newBlocks = newBlocks.map((b) =>
              b.id === action.blockId
                ? { ...b, config: (action.current?.config as DashboardBlockConfig) || b.config }
                : b,
            );
            break;
          }
        }

        return {
          ...prev,
          blocks: newBlocks,
          updated_at: new Date().toISOString(),
        };
      });

      setSaveState('unsaved');
      return prevRedo.slice(0, -1);
    });
  }, [redoStack]);

  // ═════════════════════════════════════════════════════════════
  //  AUTO-SAVE
  // ═════════════════════════════════════════════════════════════

  const doSave = useCallback(async (layoutToSave: DashboardLayout, id: number | null) => {
    setSaveState('saving');

    try {
      if (id != null) {
        // Update existing layout
        await api.put(`/dashboard/layout/${id}`, {
          blocks: layoutToSave.blocks,
        });
      } else {
        // Create new layout (first time saving)
        const response = await api.post<{ success: boolean; data: DashboardLayout }>(
          '/dashboard/layout',
          {
            layout_name: layoutToSave.layout_name || 'Default',
            blocks: layoutToSave.blocks,
            is_active: true,
          },
        );

        if (response.data?.success && response.data.data) {
          const newId = response.data.data.id;
          setLayoutId(newId);
          layoutIdRef.current = newId;
          setLayout((prev) => ({ ...prev, id: newId }));
        }
      }

      if (!isMountedRef.current) return;

      setSaveState('saved');
      retryCountRef.current = 0;
      lastSavedBlocksRef.current = layoutToSave.blocks;

      // Update localStorage with fresh data — use layoutToSave with corrected ID
      const savedId = layoutIdRef.current ?? layoutToSave.id;
      saveToLocalStorage({
        ...layoutToSave,
        id: savedId,
        updated_at: new Date().toISOString(),
      });

      toast.success('Layout saved');

      // Auto-clear "saved" indicator after 3s
      setTimeout(() => {
        if (isMountedRef.current && saveStateRef.current === 'saved') {
          setSaveState('saved');
        }
      }, 3000);
    } catch {
      if (!isMountedRef.current) return;

      if (retryCountRef.current < MAX_AUTO_RETRIES) {
        retryCountRef.current++;
        setSaveState('saveFailed');
        retryTimerRef.current = setTimeout(() => {
          if (isMountedRef.current) {
            doSave(layoutToSave, layoutIdRef.current);
          }
        }, AUTO_RETRY_DELAY_MS);
      } else {
        setSaveState('saveFailed');
        toast.error('Failed to save layout');
      }
    }
  }, []);

  const scheduleAutoSave = useCallback((updatedLayout: DashboardLayout) => {
    if (autoSaveTimerRef.current) {
      clearTimeout(autoSaveTimerRef.current);
    }

    saveToLocalStorage(updatedLayout);

    autoSaveTimerRef.current = setTimeout(() => {
      if (isMountedRef.current) {
        doSave(updatedLayout, layoutIdRef.current);
      }
    }, AUTO_SAVE_DELAY_MS);
  }, [doSave]);

  // ═════════════════════════════════════════════════════════════
  //  MANUAL SAVE
  // ═════════════════════════════════════════════════════════════

  const saveNow = useCallback(() => {
    if (autoSaveTimerRef.current) {
      clearTimeout(autoSaveTimerRef.current);
    }
    if (retryTimerRef.current) {
      clearTimeout(retryTimerRef.current);
    }
    retryCountRef.current = 0;
    doSave(layoutRef.current, layoutIdRef.current);
  }, [doSave]);

  // ═════════════════════════════════════════════════════════════
  //  RESET TO DEFAULT
  // ═════════════════════════════════════════════════════════════

  const resetToDefault = useCallback(() => {
    const defaultLayout = createDefaultLayout();
    setLayout(defaultLayout);
    setLayoutId(null);
    setLayoutName('Default');
    setUndoStack([]);
    setRedoStack([]);
    clearLocalStorageCache();
    setSaveState('unsaved');
    scheduleAutoSave(defaultLayout);

    toast.success('Layout reverted to default');
  }, [scheduleAutoSave]);

  // ═════════════════════════════════════════════════════════════
  //  RENAME LAYOUT
  // ═════════════════════════════════════════════════════════════

  const renameLayout = useCallback((name: string) => {
    setLayoutName(name);
    setLayout((prev) => ({
      ...prev,
      layout_name: name,
      updated_at: new Date().toISOString(),
    }));

    if (layoutId) {
      api.patch(`/dashboard/layout/${layoutId}/rename`, { layout_name: name })
        .catch(() => {
          // Rename failure is non-critical — don't block the user
        });
    }
  }, [layoutId]);

  // ═════════════════════════════════════════════════════════════
  //  DUPLICATE LAYOUT
  // ═════════════════════════════════════════════════════════════

  const duplicateLayout = useCallback(async (): Promise<DashboardLayout | null> => {
    if (!layoutId) return null;
    try {
      const response = await api.post<{ success: boolean; data: DashboardLayout }>(
        '/dashboard/layout/duplicate',
        { id: layoutId },
      );
      return response.data?.data || null;
    } catch {
      return null;
    }
  }, [layoutId]);

  // ═════════════════════════════════════════════════════════════
  //  IS_EDITING TOGGLE
  // ═════════════════════════════════════════════════════════════

  const setEditing = useCallback((editing: boolean) => {
    setIsEditing(editing);
    if (!editing && saveStateRef.current === 'unsaved') {
      saveNow();
    }
  }, [saveNow]);

  // ═════════════════════════════════════════════════════════════
  //  CANCEL SETTINGS (revert without marking dirty)
  // ═════════════════════════════════════════════════════════════

  const cancelBlockSettings = useCallback((
    blockId: string,
    originalTitle: string,
    originalConfig: Record<string, unknown>,
    originalWidth: number,
    originalHeight: number,
  ) => {
    setLayout((prev) => {
      const blockIndex = prev.blocks.findIndex((b) => b.id === blockId);
      if (blockIndex === -1) return prev;

      const block = prev.blocks[blockIndex];
      const updates: Partial<DashboardBlock> = {};
      let changed = false;

      if (block.title !== originalTitle) {
        updates.title = originalTitle;
        changed = true;
      }
      if (JSON.stringify(block.config) !== JSON.stringify(originalConfig)) {
        updates.config = originalConfig;
        changed = true;
      }
      if (block.width !== originalWidth || block.height !== originalHeight) {
        updates.width = originalWidth;
        updates.height = originalHeight;
        changed = true;
      }

      if (!changed) return prev;

      const newBlocks = [...prev.blocks];
      newBlocks[blockIndex] = { ...block, ...updates };
      return {
        ...prev,
        blocks: newBlocks,
        updated_at: new Date().toISOString(),
      };
    });
  }, []);

  // ═════════════════════════════════════════════════════════════
  //  EXPOSED STATE & METHODS
  // ═════════════════════════════════════════════════════════════

  return {
    // State
    blocks: layout.blocks,
    layoutId,
    layoutName,
    isEditing,

    saveState,
    isLoading,
    undoStack,
    redoStack,

    // Actions
    setEditing,
    addBlock,
    removeBlock,
    moveBlock,
    resizeBlock,
    updateBlockConfig,
    updateBlockTitle,
    undo,
    redo,
    saveNow,
    resetToDefault,
    renameLayout,
    duplicateLayout,
    cancelBlockSettings,

    // Layout metadata
    isDefaultLayout: !layoutId,
    blocksCount: layout.blocks.length,
    maxBlocksReached: layout.blocks.length >= MAX_BLOCKS,
  };
}

export default useDashboardLayout;
