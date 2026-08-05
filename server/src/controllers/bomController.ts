import { Request, Response, NextFunction } from 'express';
import BOMModel from '../models/BOM';
import { AuthRequest } from '../types';
import { logCRUD, ActionType } from '../services/activityLogger';
import db from '../config/database';
import logger from '../utils/logger';

export const getAllBOMs = (req: Request, res: Response, next: NextFunction): void => {
  try {
    const boms = BOMModel.getAll(db);
    res.json(boms);
  } catch (error) {
    next(error);
  }
};

export const getBOMById = (req: Request, res: Response, next: NextFunction): void => {
  try {
    const { id } = req.params;
    const bom = BOMModel.getById(Number(id), db);

    if (!bom) {
      res.status(404).json({ error: 'BOM not found' });
      return;
    }

    res.json(bom);
  } catch (error) {
    next(error);
  }
};

export const getBOMsByFinishedItem = (req: Request, res: Response, next: NextFunction): void => {
  try {
    const { itemId } = req.params;
    const boms = BOMModel.getByFinishedItem(Number(itemId), db);
    res.json(boms);
  } catch (error) {
    next(error);
  }
};

export const createBOM = (req: AuthRequest, res: Response, next: NextFunction): void => {
  try {
    const { finished_item_id, quantity, bom_name, items } = req.body;

    if (!finished_item_id || !quantity || !bom_name || !items || items.length === 0) {
      res.status(400).json({
        error: 'finished_item_id, quantity, bom_name, and at least one item are required'
      });
      return;
    }

    for (const item of items) {
      if (!item.item_id || !item.quantity || item.quantity <= 0) {
        res.status(400).json({
          error: 'Each item must have item_id and quantity > 0'
        });
        return;
      }
    }

    const bom = BOMModel.create(req.body, req.user!.id, db);

    logger.info(`Created BOM: ${bom.bom_no} for ${bom.finished_item_name}`);

    // Log BOM creation using activity logger
    logCRUD(ActionType.BOM_CREATE, 'BOM', bom.id, `Created BOM: ${bom.bom_no} for ${bom.finished_item_name}`, req.user!.id);
    req.activityLogged = true;

    res.status(201).json(bom);
  } catch (error) {
    next(error);
  }
};

export const updateBOM = (req: AuthRequest, res: Response, next: NextFunction): void => {
  try {
    const { id } = req.params;
    
    if (!req.user) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    const bom = BOMModel.update(Number(id), req.body, req.user.id, db);

    logger.info(`Updated BOM: ${bom.bom_no}`);

    // Log BOM update using activity logger
    logCRUD(ActionType.BOM_UPDATE, 'BOM', bom.id, `Updated BOM: ${bom.bom_no}`, req.user.id);
    req.activityLogged = true;

    res.json(bom);
  } catch (error) {
    next(error);
  }
};

export const deleteBOM = (req: AuthRequest, res: Response, next: NextFunction): void => {
  try {
    const { id } = req.params;

    const bom = BOMModel.getById(Number(id), db);

    if (!bom) {
      res.status(404).json({ error: 'BOM not found' });
      return;
    }

    BOMModel.delete(Number(id), db);

    logger.info(`Deleted BOM: ${bom.bom_no}`);

    // Log BOM deletion using activity logger
    logCRUD(ActionType.BOM_DELETE, 'BOM', Number(id), `Deleted BOM: ${bom.bom_no}`, req.user!.id);
    req.activityLogged = true;

    res.json({ message: 'BOM deleted successfully' });
  } catch (error) {
    next(error);
  }
};

export const toggleBOMActive = (req: AuthRequest, res: Response, next: NextFunction): void => {
  try {
    const { id } = req.params;

    const bom = BOMModel.toggleActive(Number(id), db);

    logger.info(`${bom.is_active ? 'Activated' : 'Deactivated'} BOM: ${bom.bom_no}`);

    res.json(bom);
  } catch (error) {
    next(error);
  }
};
