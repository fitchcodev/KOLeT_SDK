import { NativeModules, Platform } from 'react-native';

const LINKING_ERROR =
  `The package 'react-native-contactless' doesn't seem to be linked. Make sure: \n\n` +
  Platform.select({ ios: "- You have run 'pod install'\n", default: '' }) +
  '- You rebuilt the app after installing the package\n' +
  '- You are not using Expo Go\n';

const ContactlessSDK = NativeModules.ContactlessSDK
  ? NativeModules.ContactlessSDK
  : new Proxy(
      {},
      {
        get() {
          throw new Error(LINKING_ERROR);
        },
      }
    );

export interface PaymentRequest {
  amount: number;
  currency: string;
  merchantId: string;
  terminalId: string;
  metadata?: Record<string, any>;
}

export interface PaymentResult {
  success: boolean;
  transactionId?: string;
  authCode?: string;
  maskedPan?: string;
  errorMessage?: string;
  errorCode?: string;
}

/**
 * Initialize the Contactless SDK
 */
export function initialize(apiKey: string, environment: 'sandbox' | 'production' = 'sandbox'): Promise<boolean> {
  return ContactlessSDK.initialize(apiKey, environment);
}

/**
 * Start a payment session
 */
export function startPayment(request: PaymentRequest): Promise<PaymentResult> {
  return ContactlessSDK.startPayment(request);
}

/**
 * Check if NFC is available
 */
export function isNfcAvailable(): Promise<boolean> {
  return ContactlessSDK.isNfcAvailable();
}

export default {
  initialize,
  startPayment,
  isNfcAvailable,
};
