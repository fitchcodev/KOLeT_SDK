import { requireNativeModule } from 'expo-modules-core';

type PaymentRequest = {
  amount: number;
  currency: string;
  merchantId: string;
  terminalId: string;
  metadata?: Record<string, any>;
};

type PaymentResult = {
  success: boolean;
  transactionId?: string;
  authCode?: string;
  maskedPan?: string;
  errorMessage?: string;
  errorCode?: string;
};

type ContactlessSDKModule = {
  initialize(apiKey: string, environment: 'sandbox' | 'production'): Promise<boolean>;
  isNfcAvailable(): Promise<boolean>;
  startPayment(request: PaymentRequest): Promise<PaymentResult>;
};

const ContactlessSDK = requireNativeModule<ContactlessSDKModule>('ContactlessSDK');

export function initialize(apiKey: string, environment: 'sandbox' | 'production' = 'sandbox') {
  return ContactlessSDK.initialize(apiKey, environment);
}

export function isNfcAvailable() {
  return ContactlessSDK.isNfcAvailable();
}

export function startPayment(request: PaymentRequest) {
  return ContactlessSDK.startPayment(request);
}

export default {
  initialize,
  isNfcAvailable,
  startPayment,
};
