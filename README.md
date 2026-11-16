# mn_p20_plugin

Flutter plugin (chỉ Android) bọc bộ SDK phần cứng xe buýt của Magnetic North cho
đầu Android P20 / P20A / P7. Plugin đóng gói sẵn `MnSdk-1.3.1.aar` và
`MnFuelSdk-1.0.0.aar`.

| Lớp Dart | Phần cứng | Kết nối |
|---|---|---|
| `MnP20Sdk` | Thiết bị P20: GPS, IO, NFC, G-Sensor, TTS, loa, CAN, mạng, DSM, TMS, firmware | Service cục bộ |
| `MnMdvrSdk` | Đầu ghi MDVR: GPS, đếm khách, báo trạm, tuyến, gọi thoại, camera, cảnh báo, hiệu chuẩn | RS232 |
| `MnLedSdk` | Bảng LED chỉ tuyến | RS485 |
| `MnFuelSdk` | Cảm biến nhiên liệu | Serial |
| `MnCamera`, `MnCameraView` | Xem trước các kênh camera của P20 | Camera2 |

## Yêu cầu

- Thiết bị phải cài sẵn **MnSdk Service APK** (`com.amoymn.mdvrservice`). Thiếu
  nó, mọi lệnh trả về `code = -1`.
- App dùng plugin phải đặt `minSdk = 28` trở lên trong
  `android/app/build.gradle.kts`.
- Không cần khai báo quyền hay `<queries>` trong app: plugin đã khai báo sẵn
  (kể cả quyền `CAMERA`).

## Cài đặt

```yaml
dependencies:
  mn_p20_plugin:
    path: ../mn_p20_plugin
```

## Sử dụng

Mọi lệnh trả về `MnResult` với `code`, `msg`, `data`. Lỗi của SDK nằm trong
`code`, không ném exception.

```dart
import 'package:mn_p20_plugin/mn_p20_plugin.dart';

final p20 = MnP20Sdk.instance;

final init = await p20.init();
if (!init.isSuccess) {
  // -1: chưa kết nối Service, -2: lỗi, -3: timeout, -4: thiếu file cấu hình
  return;
}

final version = await p20.getVersion();
print(version.dataMap['firmware_version']);

await p20.ttsSpeak('Hello', lang: 'en'); // hoàn tất khi đọc xong
```

Dữ liệu đẩy liên tục là `Stream`. Listener native được đăng ký khi có người
nghe đầu tiên và huỷ khi người nghe cuối cùng rời đi:

```dart
final subscription = p20.locationUpdates.listen((result) {
  print('${result.dataMap['lat']}, ${result.dataMap['lng']}');
});
// ...
await subscription.cancel();
```

CAN trên P20:

```dart
p20.canFrames.listen(print);
await p20.canOpen(0, 250000);
await p20.canSend(port: 0, id: 0x18FEBF0B, extended: true, data: [0, 1, 2]);
await p20.canClose(0);
```

MDVR và LED cần cổng serial:

```dart
await MnMdvrSdk.instance.init(path: '/dev/ttyS4', baudRate: 19200);
await MnLedSdk.instance.init(path: '/dev/ttyS5', baudRate: 38400);

// LED: phải gọi getRouteList trước khi đổi tuyến hoặc báo trạm.
final routes = await MnLedSdk.instance.getRouteList();
await MnLedSdk.instance.switchRoute(index: 0, direction: 0);
```

Nhớ gọi `release()` của từng lớp khi không dùng nữa.

Xem trước camera: các kênh CH1..CH4 của P20 là camera Android thông thường,
đánh số theo thứ tự trong danh sách camera hệ thống (CH1 là `index: 0`).
`MnCameraView` tự xin quyền, mở camera khi hiển thị, mở lại khi đổi `index` và
giải phóng khi bị gỡ khỏi cây widget:

```dart
SizedBox(height: 360, child: MnCameraView(index: 0))
```

Muốn đổi kênh mà đầu ghi MDVR xuất ra thì dùng
`MnMdvrSdk.instance.switchAnalogChannels([1, 2, 3, 4])`,
`switchIpcChannel(1)` hoặc `resetToDefaultChannel()`.

## Cổng serial theo model

| Cổng | P7 / P20 | P20A |
|---|---|---|
| RS485 (LED) | `/dev/ttyS5` | `/dev/ttyS4` |
| RS232 giắc hàng không (MDVR) | `/dev/ttyS4` | `/dev/ttyS8` |
| RS232-1 | `/dev/ttyS7` | `/dev/ttyS7` |
| RS232-2 | `/dev/ttyS9` | `/dev/ttyS1` |

Mỗi node chỉ một tiến trình được mở tại một thời điểm.

## Lưu ý

- **Sau `release()` phải nghe lại stream.** SDK gốc xoá toàn bộ listener khi
  `release()`, nên các stream đang nghe sẽ ngừng nhận dữ liệu. Huỷ rồi `listen`
  lại sau lần `init()` kế tiếp.
- **Một số stream gửi gói xác nhận trước.** Ví dụ `routeStatus`,
  `displayMessages`, `alarms` phát một `MnResult` có `data` rỗng ngay sau khi
  đăng ký, rồi mới đến dữ liệu thật.
- **Lệnh không có timeout ở phía plugin.** `Future` hoàn tất khi SDK gốc gọi
  callback. Nếu cần giới hạn thời gian, dùng `.timeout(...)` ở phía Dart.
- **Lệnh nguy hiểm.** `rebootDevice()` và `upgradeFirmware()` khởi động lại máy
  ngay; firmware sai có thể làm máy không boot được. `execRootShell()` chạy lệnh
  với quyền root.
- **API chưa được nhà sản xuất chốt định dạng.** `driverAttendance`,
  `queryHostStatus`, `querySmsContent`, `queryContacts` trả về dữ liệu theo giao
  thức của đầu ghi; cần thử trên thiết bị thật.

## Cấu trúc

- `lib/` — API Dart: mỗi facade một file trong `lib/src/`.
- `android/src/main/kotlin/` — `MnP20Plugin.kt`, cầu nối MethodChannel /
  EventChannel sang SDK gốc.
- `android/maven/` — hai file AAR của nhà sản xuất, đóng thành Maven repo cục
  bộ. Để nâng phiên bản: thêm thư mục phiên bản mới (file `.aar` và `.pom`) rồi
  sửa số phiên bản trong `android/build.gradle.kts`.
- `example/` — app thử từng lệnh và từng stream, tương đương app demo gốc.

## Kiểm thử

```sh
flutter test                              # test phần Dart
cd example && flutter build apk --debug   # build app ví dụ
```
