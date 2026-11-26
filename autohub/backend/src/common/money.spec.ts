import { settle, taxFromInclusive } from './money';

const rates = { gstOnCommissionBps: 1800, tcsBps: 100, tdsBps: 10 };

describe('money', () => {
  it('extracts GST from an inclusive price', () => {
    expect(taxFromInclusive(299800, 1800)).toBe(45732);
    expect(taxFromInclusive(0, 1800)).toBe(0);
  });

  it('settles the ₹2,998 brake-pad order from the API spec', () => {
    expect(settle(299800, 254068, 800, rates)).toEqual({
      grossPaise: 299800, taxableValuePaise: 254068, commissionBps: 800,
      commissionPaise: 23984, commissionGstPaise: 4317, tcsPaise: 2541, tdsPaise: 254, vendorPayoutPaise: 268704,
    });
  });

  it('payout always equals gross minus every deduction', () => {
    for (const gross of [100, 9999, 123457, 9_999_999]) {
      const s = settle(gross, Math.round(gross / 1.18), 1200, rates);
      expect(s.vendorPayoutPaise).toBe(gross - s.commissionPaise - s.commissionGstPaise - s.tcsPaise - s.tdsPaise);
    }
  });
});
