import 'dart:io';

import 'package:dio/dio.dart';
import 'package:exploraec/controllers/auth_controller.dart';
import 'package:exploraec/main.dart';
import 'package:exploraec/services/ai_assistant_service.dart';
import 'package:exploraec/services/api_client.dart';
import 'package:exploraec/services/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

void main() {
  setUpAll(() {
    Hive.init(Directory.systemTemp.createTempSync('hive_widget_test').path);
  });

  tearDown(() async {
    Get.reset();
  });

  testWidgets('ExploraEcApp carga la pantalla inicial con la barra de navegación', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await Hive.deleteFromDisk();
      FlutterSecureStorage.setMockInitialValues({});
      await Hive.openBox<Map>('favoritos');
      await SettingsService.abrir();

      Get.put(ApiClient(dio: Dio(BaseOptions(baseUrl: 'http://prueba'))), permanent: true);
      Get.put(AuthController(), permanent: true);
      Get.put(AiAssistantService(), permanent: true);
    });

    await tester.pumpWidget(const ExploraEcApp());
    await tester.pump();

    // Verifica que se muestre la barra de navegación con los accesos principales
    expect(find.byIcon(Icons.home), findsOneWidget);
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    expect(find.byIcon(Icons.receipt_long), findsOneWidget);
    expect(find.byIcon(Icons.auto_awesome), findsOneWidget);

    // Navegar a la pestaña de favoritos
    await tester.tap(find.byIcon(Icons.favorite));
    await tester.pump();

    expect(find.widgetWithText(AppBar, 'Favoritos'), findsOneWidget);
    expect(find.textContaining('Todavía no marcaste ningún lugar como favorito'), findsOneWidget);

    // Navegar a la pestaña de gastos
    await tester.tap(find.byIcon(Icons.receipt_long));
    await tester.pump();

    expect(find.text('Inicia sesión para continuar.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Iniciar sesión'), findsOneWidget);

    // Permitir que el temporizador de carga inicial de lugares termine
    await tester.pump(const Duration(seconds: 2));
  });
}
