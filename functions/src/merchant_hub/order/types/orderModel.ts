// Base type for common order fields
type BaseOrder = {
  createdAt: Date;
  updatedAt: Date;
  confirmation: string; // pending, confirmed, etc.
  merchantId: string;
  accepted: boolean;
  customerId: string;
};

// Specific type for Airtime Orders
export type AirtimeOrder = BaseOrder & {
  mobileNumber: string;
  airtimeRechargeAmount: number;
  mobileProvider: string;
};

// Specific type for Electricity Orders
export type ElectricityOrder = BaseOrder & {
  meterNumber: string;
  electricityMobileNumber: string;
  electricityRechargeAmount: number;
};

// Union type for either order type
export type Order = AirtimeOrder | ElectricityOrder;
