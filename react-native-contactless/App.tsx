import React, { useState } from 'react';
import { SafeAreaView, StyleSheet, Text, TextInput, View, Button, Platform, Alert } from 'react-native';
import { StatusBar } from 'expo-status-bar';
import ContactlessSDK from 'contactless-sdk-module';

export default function App() {
  const [apiKey, setApiKey] = useState('');

  const onPress = () => {
    Alert.alert('Expo app created', `Running on ${Platform.OS}.\n\nNext: run prebuild to generate ios/ and android/ folders.`);
  };

  const onCheckNfc = async () => {
    try {
      const available = await ContactlessSDK.isNfcAvailable();
      Alert.alert('NFC availability', available ? 'NFC available' : 'NFC not available');
    } catch (e: any) {
      Alert.alert('Error', e?.message ?? String(e));
    }
  };

  const onInitialize = async () => {
    try {
      const ok = await ContactlessSDK.initialize(apiKey, 'sandbox');
      Alert.alert('Initialize', ok ? 'Initialized' : 'Failed');
    } catch (e: any) {
      Alert.alert('Error', e?.message ?? String(e));
    }
  };

  const onStartPayment = async () => {
    try {
      const result = await ContactlessSDK.startPayment({
        amount: 1,
        currency: 'USD',
        merchantId: 'M123',
        terminalId: 'T456',
      });
      Alert.alert('Payment result', JSON.stringify(result, null, 2));
    } catch (e: any) {
      Alert.alert('Error', e?.message ?? String(e));
    }
  };

  return (
    <SafeAreaView style={styles.container}>
      <StatusBar style="auto" />
      <View style={styles.content}>
        <Text style={styles.title}>Contactless Expo App</Text>
        <Text style={styles.subtitle}>This is a placeholder UI. Your native module can be wired in after prebuild.</Text>

        <Text style={styles.label}>API key</Text>
        <TextInput
          value={apiKey}
          onChangeText={setApiKey}
          placeholder="Enter API key"
          autoCapitalize="none"
          style={styles.input}
        />

        <Button title="Initialize" onPress={onInitialize} />
        <Button title="Check NFC" onPress={onCheckNfc} />
        <Button title="Start Payment" onPress={onStartPayment} />
        <Button title="Prebuild reminder" onPress={onPress} />
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#fff',
  },
  content: {
    flex: 1,
    padding: 20,
    gap: 12,
  },
  title: {
    fontSize: 24,
    fontWeight: '700',
  },
  subtitle: {
    fontSize: 14,
    color: '#555',
    marginBottom: 8,
  },
  label: {
    fontSize: 14,
    fontWeight: '600',
  },
  input: {
    borderWidth: 1,
    borderColor: '#ddd',
    paddingHorizontal: 12,
    paddingVertical: 10,
    borderRadius: 8,
    fontSize: 16,
  },
});
