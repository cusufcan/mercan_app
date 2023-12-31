import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../constant/app_constant.dart';
import '../data/shared_manager.dart';
import '../widget/update_dialog.dart';
import '../widget/yemekhane_widget.dart';

class GopMenu extends StatefulWidget {
  const GopMenu({super.key});

  @override
  State<GopMenu> createState() => _GopMenuState();
}

class _GopMenuState extends State<GopMenu> {
  SharedManager? _sharedManager;
  String? _weekDataGlobal;
  List<List<String>> _data = List.empty(growable: true);

  Future<List<List<String>>> _init() async {
    // Uygulamaya güncellemelerini kontrol et
    bool hasNetwork = await _hasNetwork();
    if (hasNetwork) {
      // Kullanıcının device tokenini sunucuya gönder ki giriş yaptığı belli olsun.
      final FirebaseMessaging firebaseMessaging = FirebaseMessaging.instance;
      final String deviceToken = await firebaseMessaging.getToken() ?? "";

      var db = FirebaseFirestore.instance;

      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      final String buildNumber = packageInfo.buildNumber;
      await db.collection("update").doc("version").get().then((event) async {
        var networkVersion = event['version'];
        var isOptionalString = event['isOptional'];
        var title = event['title'];
        var content = event['message'];
        var button = event['button'];
        List whiteList = event['whitelist'];
        final bool isOptional = isOptionalString == "true" ? true : false;
        var currentVersion = buildNumber;
        if (networkVersion != currentVersion && !whiteList.contains(deviceToken)) {
          await showDialog(
            context: context,
            builder: (context) => WillPopScope(
              onWillPop: () => Future.value(isOptional),
              child: UpdateDialog(
                isOptional: isOptional,
                title: title,
                content: content,
                button: button,
              ),
            ),
            barrierDismissible: isOptional,
          );
        }
      });

      int loginTime = 0;
      await db.collection("general").doc("devices").get().then((value) {
        value.data()?.forEach((key, value) {
          if (key == deviceToken) {
            loginTime = value;
          }
        });
      });

      await db.collection("general").doc("devices").set(
        {
          deviceToken: ++loginTime,
        },
        SetOptions(merge: true),
      );
    }

    // Her build edildiğinde listeyi temizle
    _data = List.empty(growable: true);

    // SharedManager Initialize
    _sharedManager = SharedManager();
    await _sharedManager!.init();

    if (!_sharedManager!.hasKeyGlobal(SharedKeysGlobal.build12RESET)) {
      await _sharedManager!.clearAll();
      await _sharedManager!.saveStringItemGlobal(SharedKeysGlobal.build12RESET, "true");
      debugPrint("buraya girdi");
    }

    // Kayıtlı veri var mı diye bak
    bool hasKey = _checkSaveData(SharedKeysGOP.dateGop);

    if (hasKey) {
      // Kayıtlı veriyi getir
      debugPrint('Kullanıcının kayıtlı verisi var ve kayıtlı veriyi getiriyorum.');
      return _getSavedData();
    } else {
      // İnternetten veri getir
      debugPrint('Kullanıcının kayıtlı verisi yok ve internetten veri çekiyorum.');
      await _getWebData();
      await _saveData();
    }

    return [
      ['N/A']
    ];
  }

  bool _checkSaveData(SharedKeysGOP key) {
    bool hasKey = _sharedManager!.hasKey(key);
    if (hasKey) {
      return true;
    } else {
      return false;
    }
  }

  Future<List<List<String>>> _getSavedData() async {
    bool isOnline = await _hasNetwork();
    if (isOnline) {
      debugPrint('İnternet olduğu için günleri kontrol edip ona göre veriyi getiriyorum.');
      String weekDataOnline = await _getWeekDataOnline();
      String weekDataSaved = _getWeekDataSaved();
      _weekDataGlobal = weekDataOnline;
      if (weekDataOnline == weekDataSaved) {
        for (var i = 0; i < 5; i++) {
          _data.add(_sharedManager!.getStringItems(SharedKeysGOP.values.elementAt(i)) ?? ['N/A']);
        }
      } else {
        await _getWebData();
      }
    } else {
      debugPrint('İnternet olmadığı için en son kaydedilen veriyi getiriyorum.');
      String weekDataSaved = _getWeekDataSaved();
      _weekDataGlobal = weekDataSaved;
      for (var i = 0; i < 5; i++) {
        _data.add(_sharedManager!.getStringItems(SharedKeysGOP.values.elementAt(i)) ?? ['N/A']);
      }
    }
    return _data;
  }

  Future<void> _saveData() async {
    if (_data.isNotEmpty && _data.every((element) => !element.contains("Menü girilmemiş"))) {
      if (_data.first != ['N/A']) {
        String weekDataOnline = await _getWeekDataOnline();
        _sharedManager!.saveStringItem(SharedKeysGOP.dateGop, weekDataOnline);
        _weekDataGlobal = weekDataOnline;
        for (var i = 0; i < 5; i++) {
          _sharedManager!.saveStringItems(SharedKeysGOP.values.elementAt(i), _data.elementAt(i));
        }
      } else {
        debugPrint('Data NULL');
      }
    }
  }

  Future<void> _getWebData() async {
    final url = Uri.parse('https://sosyaltesisler.gop.edu.tr/yemekhane_menu.aspx');
    final response = await http.get(url);
    final body = response.body;
    final document = parser.parse(body);
    var data = document.getElementsByClassName('style19').toList();
    List<List<String>> returnData = [];
    for (var i = 5; i < data.length; i++) {
      // Her satırı al ve boşlukları temizle
      List<String> lines = data.elementAt(i).text.split('\n');
      lines = lines.map((line) => line.trim()).toList();

      // Boş satırları kaldır
      lines.removeWhere((line) => line.isEmpty);

      // Son iki satırı birleştir
      if (lines.length > 1) {
        final lastElement = lines.removeLast();
        final secondLastElement = lines.removeLast();
        lines.add('$secondLastElement $lastElement');
      }

      // Temizlenmiş metni gönderilecek veriye ekle
      returnData.add(lines);
    }
    _data = returnData;
    await _saveData();
  }

  Future<String> _getWeekDataOnline() async {
    final url = Uri.parse('https://sosyaltesisler.gop.edu.tr/yemekhane_menu.aspx');
    final response = await http.get(url);
    final body = response.body;
    final document = parser.parse(body);
    var data = document.getElementById('ContentPlaceHolder1_haftaBasi');
    return data!.text.toString();
  }

  String _getWeekDataSaved() {
    String weekData = _sharedManager!.getStringItem(SharedKeysGOP.dateGop) ?? 'N/A';
    return weekData;
  }

  Future<bool> _hasNetwork() async {
    try {
      final result = await InternetAddress.lookup('example.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConstants.title),
        centerTitle: true,
      ),
      body: FutureBuilder(
        future: _init(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return YemekhaneWidget(
              data: _data,
              weekData: weekData,
            );
          } else {
            return const Center(child: CircularProgressIndicator.adaptive());
          }
        },
      ),
    );
  }

  String? get weekData {
    String? reversedData = _weekDataGlobal?.split('.').reversed.join('-');
    if (reversedData != null) {
      DateTime tempDateFirst = DateTime.parse(reversedData);
      DateTime tempDateLast = tempDateFirst.add(const Duration(days: 4));
      return "${DateFormat('dd.MM.yyyy').format(tempDateFirst)} - ${DateFormat('dd.MM.yyyy').format(tempDateLast)}";
    }
    return null;
  }
}
