import type { Response } from 'express';
import type { AuthRequest } from '../types';
import db from '../config/database';
import { PartyModel } from '../models/Party';
import { PartyAdjustmentService } from '../services/PartyAdjustmentService';
import { BusinessRuleError, handleBusinessError } from '../utils/businessRuleError';
import { partyCustomerInput, partyLinkInput, partySupplierInput } from '../types/party';

const parties = new PartyModel(db);
const adjustments = new PartyAdjustmentService(db);

function positiveId(value: unknown): number {
  const id = Number(value);
  if (!Number.isSafeInteger(id) || id <= 0) throw new BusinessRuleError(400,'Invalid identifier');
  return id;
}

function respond(operation: (req: AuthRequest) => unknown, status = 200) {
  return (req: AuthRequest,res: Response): void => {
    try {
      if (!req.user) throw new BusinessRuleError(401,'Authentication is required');
      res.status(status).json({ success:true,data:operation(req) });
    } catch (error: unknown) { handleBusinessError(res,error,'Party operation','Unable to complete the Party operation'); }
  };
}

function userId(req: AuthRequest): number {
  if (!req.user) throw new BusinessRuleError(401,'Authentication is required');
  return req.user.id;
}

export const getPartyPosition = respond(req=>parties.position(positiveId(req.params.id)));
export const getPartyTargets = respond(req=>parties.targets(positiveId(req.params.id)));
export const getPartyAdjustment = respond(req=>adjustments.get(positiveId(req.params.id),positiveId(req.params.adjustmentId)));
export const postPartyAdjustment = respond(req=>adjustments.postAdjustment(positiveId(req.params.id),req.body,userId(req),req.headers),201);
export const reversePartyAdjustment = respond(req=>adjustments.reverseAdjustment(positiveId(req.params.id),positiveId(req.params.adjustmentId),req.body,userId(req)));
export const unlinkParty = respond(req=>parties.unlink(positiveId(req.params.id),userId(req)));

export const linkParty = respond(req=>{
  const input = partyLinkInput.safeParse(req.body);
  if (!input.success) throw new BusinessRuleError(400,'Customer and supplier IDs, and confirmation, are required');
  return parties.link(input.data.customer_id,input.data.supplier_id,userId(req));
});
export const addPartyCustomer = respond(req=>{
  const input = partyCustomerInput.safeParse(req.body);
  if (!input.success) throw new BusinessRuleError(400,input.error.issues[0]?.message ?? 'Invalid customer');
  return parties.addCustomer(positiveId(req.params.id),input.data,userId(req));
},201);
export const addPartySupplier = respond(req=>{
  const input = partySupplierInput.safeParse(req.body);
  if (!input.success) throw new BusinessRuleError(400,input.error.issues[0]?.message ?? 'Invalid supplier');
  return parties.addSupplier(positiveId(req.params.id),input.data,userId(req));
},201);

export function listPartyAdjustments(req: AuthRequest,res: Response): void {
  try {
    const page = positiveId(req.query.page ?? 1);
    const limit = positiveId(req.query.limit ?? 25);
    if (limit > 100) throw new BusinessRuleError(400,'Page size must not exceed 100');
    const result = adjustments.list(positiveId(req.params.id),page,limit);
    res.json({ success:true,data:result.data,pagination:{ currentPage:page,totalPages:Math.max(1,Math.ceil(result.total/limit)),
      totalItems:result.total,hasNext:page*limit<result.total,hasPrev:page>1 } });
  } catch (error: unknown) { handleBusinessError(res,error,'List Party adjustments','Unable to load adjustments'); }
}
