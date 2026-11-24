// OSORI 보행자 뱃지 펌웨어 (ESP32-C3 SuperMini)
// - Minew MWB01 비콘의 RSSI 를 스캔해 거리 단계(IDLE / WARNING / HYPER)를 판단하고 진동 모터를 구동
// - 같은 판단을 OSORI-BADGE 이름의 BLE(Nordic UART)로 폰 앱(Osori-FE)에 notify
//
// 보드: esp32:esp32:esp32c3:CDCOnBoot=cdc  (esp32 core 2.0.17)
// 라이브러리: NimBLE-Arduino 1.4.3

#include <NimBLEDevice.h>
#include <algorithm>
#include <cctype>
#include <cmath>

static const char* TARGET_MAC = "c3:00:00:8c:07:53";
static const bool USE_MAC_FILTER = true;

static int TH_M = -65;      // 약한 진동 진입
static int TH_H = -55;      // 강한 진동 진입
static int TH_H_DOWN = -59; // 강한 -> 약한 복귀 (히스테리시스)
static int TH_OFF = -68;    // 완전 꺼짐

static float tM_needed = 0.5f;
static float tH_needed = 0.4f;
static float tDown_needed = 0.3f;
static float tOff_needed = 0.2f;

static const uint32_t SAMPLE_PERIOD_MS = 100;
static const int VIB_PIN = 4;

static const uint32_t WARN_ON_MS  = 150;
static const uint32_t WARN_OFF_MS = 650;

static const char* NUS_SERVICE_UUID = "6e400001-b5a3-f393-e0a9-e50e24dcca9e";
static const char* NUS_TX_UUID      = "6e400003-b5a3-f393-e0a9-e50e24dcca9e";

typedef enum { IDLE=0, WARNING=1, HYPER=2 } State;
static State state = IDLE;

static volatile int latestRssi = -999;
static volatile uint32_t lastSeenMs = 0;
static volatile bool hasNewPkt = false;

static float smoothRssi = -120.0f;
static bool hasValidSmooth = false;

static float tM_acc = 0.0f, tH_acc = 0.0f, tDown_acc = 0.0f, tOff_acc = 0.0f;
static bool vibOn = false;
static uint32_t patternLastToggleMs = 0, lastSampleMs = 0, alertStartMs = 0;
static int hitCount = 0;

static NimBLEScan* pScan = nullptr;
static NimBLEServer* pServer = nullptr;
static NimBLECharacteristic* pTxChar = nullptr;
static volatile bool bleClientConnected = false;

class ServerCallbacks : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer* s) override { bleClientConnected = true; }
  void onDisconnect(NimBLEServer* s) override {
    bleClientConnected = false;
    NimBLEDevice::startAdvertising();
  }
};

bool matchBeacon(NimBLEAdvertisedDevice* dev) {
  if (!USE_MAC_FILTER) return true;
  std::string addr = dev->getAddress().toString();
  std::string target = TARGET_MAC;
  std::transform(addr.begin(), addr.end(), addr.begin(), [](unsigned char c){ return std::tolower(c); });
  std::transform(target.begin(), target.end(), target.begin(), [](unsigned char c){ return std::tolower(c); });
  return addr == target;
}

class ScanCallbacks : public NimBLEAdvertisedDeviceCallbacks {
  void onResult(NimBLEAdvertisedDevice* advertisedDevice) override {
    if (!matchBeacon(advertisedDevice)) return;
    latestRssi = advertisedDevice->getRSSI();
    lastSeenMs = millis();
    hasNewPkt = true;
  }
};
static ScanCallbacks callbacks;

void sendBleAlert(State s, int rssi, uint32_t durMs, int cnt) {
  if (!bleClientConnected || !pTxChar) return;
  const char* lvl = (s == HYPER) ? "DANGER" : "CAUTION";
  float dist = powf(10.0f, (-59.0f - (float)rssi) / 20.0f);
  if (dist < 0.1f) dist = 0.1f;
  char buf[192];
  int len = snprintf(buf, sizeof(buf),
    "{\"max_rssi\":%d,\"min_estimated_distance\":%.1f,\"consecutive_count\":%d,\"alert_level\":\"%s\",\"vibration_triggered\":true,\"duration_ms\":%lu}\n",
    rssi, dist, cnt, lvl, (unsigned long)durMs);
  for (int i = 0; i < len; i += 20) {
    int chunk = (len - i > 20) ? 20 : (len - i);
    pTxChar->setValue((uint8_t*)(buf + i), chunk);
    pTxChar->notify();
    delay(10);
  }
}

void setVibration(bool on) {
  vibOn = on;
  digitalWrite(VIB_PIN, on ? HIGH : LOW);
}

void resetPattern(State s) {
  patternLastToggleMs = millis();
  if (s == IDLE) setVibration(false);
  else setVibration(true);
}

void updateVibration(State s) {
  uint32_t now = millis();
  if (s == IDLE) { if (vibOn) setVibration(false); return; }
  if (s == HYPER) { if (!vibOn) setVibration(true); return; }
  if (!vibOn && (now - patternLastToggleMs >= WARN_OFF_MS)) {
    setVibration(true);
    patternLastToggleMs = now;
  } else if (vibOn && (now - patternLastToggleMs >= WARN_ON_MS)) {
    setVibration(false);
    patternLastToggleMs = now;
  }
}

void setup() {
  Serial.begin(115200);
  delay(500);
  pinMode(VIB_PIN, OUTPUT);
  setVibration(true); delay(120); setVibration(false);

  NimBLEDevice::init("OSORI-BADGE");
  pServer = NimBLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());
  NimBLEService* pSvc = pServer->createService(NUS_SERVICE_UUID);
  pTxChar = pSvc->createCharacteristic(NUS_TX_UUID, NIMBLE_PROPERTY::NOTIFY);
  pSvc->start();
  NimBLEAdvertising* pAdv = NimBLEDevice::getAdvertising();
  pAdv->addServiceUUID(NUS_SERVICE_UUID);
  pAdv->setScanResponse(true);
  pAdv->start();

  pScan = NimBLEDevice::getScan();
  pScan->setAdvertisedDeviceCallbacks(&callbacks, true);
  pScan->setActiveScan(true);
  pScan->setInterval(45);
  pScan->setWindow(35);
  pScan->setMaxResults(0);
  pScan->start(0, nullptr, false);

  lastSampleMs = millis();
  resetPattern(IDLE);
  Serial.println("OSORI v5 (-65/-55 + BLE App) Started.");
}

void loop() {
  uint32_t now = millis();
  if (now - lastSampleMs < SAMPLE_PERIOD_MS) return;
  float dt = (now - lastSampleMs) / 1000.0f;
  lastSampleMs = now;

  if (pScan && !pScan->isScanning()) {
    pScan->start(0, nullptr, false);
  }

  uint32_t age = (lastSeenMs == 0) ? 99999 : (now - lastSeenMs);
  if (age > 1800) {
    hasValidSmooth = false;
    smoothRssi = -120.0f;
  } else if (hasNewPkt) {
    hasNewPkt = false;
    int raw = (int)latestRssi;
    if (!hasValidSmooth) {
      smoothRssi = (float)raw;
      hasValidSmooth = true;
    } else {
      smoothRssi = 0.3f * smoothRssi + 0.7f * (float)raw;
    }
  }

  int rssi = (int)(smoothRssi - 0.5f);

  if (rssi >= TH_H) tH_acc += dt; else tH_acc = 0.0f;
  if (rssi >= TH_M) tM_acc += dt; else tM_acc = 0.0f;
  if (rssi < TH_H_DOWN) tDown_acc += dt; else tDown_acc = 0.0f;
  if (rssi < TH_OFF) tOff_acc += dt; else tOff_acc = 0.0f;

  State prev = state;
  if (state == IDLE) {
    if (tH_acc >= tH_needed) state = HYPER;
    else if (tM_acc >= tM_needed) state = WARNING;
  } else if (state == WARNING) {
    if (tH_acc >= tH_needed) state = HYPER;
    else if (tOff_acc >= tOff_needed) state = IDLE;
  } else if (state == HYPER) {
    if (tOff_acc >= tOff_needed) state = IDLE;
    else if (tDown_acc >= tDown_needed) state = WARNING;
  }

  if (state != prev) {
    resetPattern(state);
    if (state == IDLE) {
      hitCount = 0;
    } else {
      if (prev == IDLE) alertStartMs = now;
      hitCount++;
      sendBleAlert(state, rssi, now - alertStartMs, hitCount);
    }
  }
  updateVibration(state);

  Serial.printf("v5 raw=%d smooth=%d age=%lums state=%d vib=%d ble=%d\n",
                (age <= 1800) ? (int)latestRssi : -120, rssi,
                (unsigned long)age, (int)state, vibOn ? 1 : 0, bleClientConnected ? 1 : 0);
}
