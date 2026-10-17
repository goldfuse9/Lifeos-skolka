// Ukázka pro LifeOS (React Native): obrazovka „Platby za školku“.
// Data: supabase.rpc('moje_platby') — viz docs/PLATBY-Z-BANKY.md.
// Balíčky: react-native-qrcode-svg, react-native-svg, expo-clipboard, expo-media-library.
import React, { useCallback, useRef, useState } from 'react';
import { View, Text, Pressable, ScrollView, RefreshControl } from 'react-native';
import { useFocusEffect } from '@react-navigation/native';
import QRCode from 'react-native-qrcode-svg';
import * as Clipboard from 'expo-clipboard';
import * as MediaLibrary from 'expo-media-library';
import * as FileSystem from 'expo-file-system';

const kc = (x) => Number(x).toLocaleString('cs-CZ', { minimumFractionDigits: 0, maximumFractionDigits: 2 }) + ' Kč';

export default function PlatbySkolka({ supabase }) {
  const [deti, setDeti] = useState([]);
  const [nacitam, setNacitam] = useState(false);

  const nacti = useCallback(async () => {
    setNacitam(true);
    const { data, error } = await supabase.rpc('moje_platby');
    if (!error) setDeti(data || []);
    setNacitam(false);
  }, [supabase]);
  useFocusEffect(useCallback(() => { nacti(); }, [nacti]));   // po návratu z banky se stav obnoví

  return (
    <ScrollView refreshControl={<RefreshControl refreshing={nacitam} onRefresh={nacti} />} contentContainerStyle={{ padding: 16, gap: 16 }}>
      {deti.map((d) => <KartaDitete key={d.dite_id} d={d} />)}
    </ScrollView>
  );
}

function KartaDitete({ d }) {
  const qrRef = useRef(null);
  const ulozQr = () => qrRef.current?.toDataURL(async (png) => {
    const { granted } = await MediaLibrary.requestPermissionsAsync();
    if (!granted) return;
    const soubor = FileSystem.cacheDirectory + `platba-${d.vs}.png`;
    await FileSystem.writeAsStringAsync(soubor, png, { encoding: FileSystem.EncodingType.Base64 });
    await MediaLibrary.saveToLibraryAsync(soubor);   // bankovní aplikace: Platba → QR → z galerie
  });

  if (!d.qr) {
    return (
      <View style={{ padding: 16, borderRadius: 20, backgroundColor: '#EAF3E0' }}>
        <Text style={{ fontWeight: '800', fontSize: 17 }}>{d.jmeno}</Text>
        <Text>Vše zaplaceno{d.preplatek > 0 ? ` · přeplatek ${kc(d.preplatek)} se odečte příště` : ''}</Text>
      </View>
    );
  }
  return (
    <View style={{ padding: 16, borderRadius: 20, backgroundColor: d.po_splatnosti ? '#FBE9E2' : '#FFFFFF', gap: 10 }}>
      <Text style={{ fontWeight: '800', fontSize: 17 }}>{d.jmeno}</Text>
      <Text style={{ fontSize: 28, fontWeight: '800' }}>{kc(d.k_uhrade)}</Text>
      <Text>{d.po_splatnosti ? 'Po splatnosti' : `Splatné do ${new Date(d.splatnost).toLocaleDateString('cs-CZ')}`}</Text>
      <View style={{ alignItems: 'center', padding: 12, backgroundColor: '#FFFFFF' }}>
        <QRCode value={d.qr} size={220} ecl="M" getRef={(r) => (qrRef.current = r)} />
      </View>
      <Pressable onPress={ulozQr}><Text style={{ fontWeight: '800' }}>Uložit QR do galerie</Text></Pressable>
      {[['Účet', d.ucet], ['Částka', String(d.k_uhrade).replace('.', ',')], ['Variabilní symbol', d.vs]].map(([k, v]) => (
        <Pressable key={k} onPress={() => Clipboard.setStringAsync(v)} style={{ flexDirection: 'row', justifyContent: 'space-between' }}>
          <Text>{k}</Text><Text style={{ fontWeight: '700' }}>{v}  ⧉</Text>
        </Pressable>
      ))}
      <Text style={{ fontSize: 12, color: '#5A5C60' }}>Platba se tu ukáže jako zaplacená do pár minut po připsání na účet školky.</Text>
    </View>
  );
}
