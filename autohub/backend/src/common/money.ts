/**
 * All amounts are integer paise. Rounding is half-up to the nearest paisa, once per figure.
 * Rates are basis points (1800 = 18%).
 */
export const bpsOf = (amountPaise: number, bps: number) => Math.round((amountPaise * bps) / 10_000);

/** GST contained in a tax-inclusive price (MRP-style): 149900 @ 18% → 22866 */
export const taxFromInclusive = (inclusivePaise: number, gstBps: number) =>
  Math.round((inclusivePaise * gstBps) / (10_000 + gstBps));

export interface SettlementRates { gstOnCommissionBps: number; tcsBps: number; tdsBps: number }

export interface Settlement {
  grossPaise: number;
  taxableValuePaise: number;
  commissionBps: number;
  commissionPaise: number;
  commissionGstPaise: number;
  tcsPaise: number;
  tdsPaise: number;
  vendorPayoutPaise: number;
}

/**
 * Marketplace settlement for one order/booking.
 *  commission     = rate × gross (what the customer paid)
 *  GST on fee     = 18% × commission (platform's own GST invoice to the vendor)
 *  TCS  (GST s.52)      = 1% × taxable value (gross excluding GST)
 *  TDS  (IT  s.194-O)   = 0.1% × taxable value
 * Rates come from config; have a CA confirm the bases before launch.
 */
export function settle(grossPaise: number, taxableValuePaise: number, commissionBps: number, r: SettlementRates): Settlement {
  const commissionPaise = bpsOf(grossPaise, commissionBps);
  const commissionGstPaise = bpsOf(commissionPaise, r.gstOnCommissionBps);
  const tcsPaise = bpsOf(taxableValuePaise, r.tcsBps);
  const tdsPaise = bpsOf(taxableValuePaise, r.tdsBps);
  return {
    grossPaise, taxableValuePaise, commissionBps, commissionPaise, commissionGstPaise, tcsPaise, tdsPaise,
    vendorPayoutPaise: grossPaise - commissionPaise - commissionGstPaise - tcsPaise - tdsPaise,
  };
}
