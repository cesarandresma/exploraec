
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:exploraec/controllers/auth_controller.dart';
import 'package:exploraec/controllers/gastos_controller.dart';
import 'package:exploraec/i18n/app_translations.dart';
import 'package:exploraec/screens/gastos_screen.dart';
import 'package:exploraec/services/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

/// Servidor falso en memoria para la prueba de filtro de gastos.
class _Servidor implements HttpClientAdapter {
  final gastos = <Map<String, dynamic>>[];

  ResponseBody _json(Object? cuerpo, int codigo) =>
      ResponseBody.fromString(
        cuerpo == null ? '' : jsonEncode(cuerpo),
        codigo,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? cuerpo,
    Future<void>? cancelar,
  ) async {
    final ruta = o.path;

    if (ruta == '/usuarios/token') {
      return _json({
        'access_token': 'tok-prueba',
        'token_type': 'bearer',
      }, 200);
    }

    if (ruta == '/usuarios/me') {
      return _json({
        'id': 1,
        'email': 'viajero@exploraec.com',
      }, 200);
    }

    if (ruta == '/gastos/categorias') {
      return _json({
        'categorias': [
          'comida',
          'transporte',
          'hospedaje',
        ],
        'limite_por_categoria': 500.0,
      }, 200);
    }

    if (ruta == '/gastos/' && o.method == 'GET') {
      return _json(gastos, 200);
    }

    return _json({
      'detail': 'Ruta no prevista: $ruta',
    }, 404);
  }

  @override
  void close({bool force = false}) {}
}

/// Espera una condición y genera un error descriptivo si no se cumple.
Future<void> _esperar(
  bool Function() condicion, {
  String mensaje = 'La condición no se cumplió',
  Duration timeout = const Duration(seconds: 5),
}) async {
  final limite = DateTime.now().add(timeout);

  while (!condicion()) {
    if (DateTime.now().isAfter(limite)) {
      throw TimeoutException(mensaje);
    }

    await Future<void>.delayed(
      const Duration(milliseconds: 20),
    );
  }
}

void main() {
  setUpAll(() {
    Hive.init(
      Directory.systemTemp.createTempSync('hive_filtro').path,
    );
  });

  late _Servidor servidor;

  Future<GastosController> montarConGastos(
    List<Map<String, dynamic>> listaGastos,
  ) async {
    Get.reset();
    Get.testMode = true;

    await Hive.deleteFromDisk();
    FlutterSecureStorage.setMockInitialValues({});

    servidor = _Servidor();
    servidor.gastos.addAll(listaGastos);

    final dio = Dio(
      BaseOptions(baseUrl: 'http://prueba'),
    );
    dio.httpClientAdapter = servidor;

    Get.put(ApiClient(dio: dio));

    final auth = Get.put(AuthController());

    await _esperar(
      () => !auth.restaurando.value,
      mensaje: 'La restauración de autenticación no terminó',
    );

    await auth.iniciarSesion(
      'viajero@exploraec.com',
      'clave-1234',
    );

    final controller = Get.put(GastosController());

    await _esperar(
      () => controller.categorias.isNotEmpty,
      mensaje: 'No se cargaron las categorías de gastos',
    );

    await _esperar(
      () => controller.estado.value.name == 'exito',
      mensaje: 'La carga de gastos no llegó al estado exito',
    );

    return controller;
  }

  testWidgets(
    'al elegir «comida», solo se ven los gastos de comida',
    (tester) async {
      await montarConGastos([
        {
          'id': 1,
          'descripcion': 'Ceviche de camarón',
          'monto': 8.50,
          'categoria': 'comida',
          'fecha': '2026-10-14',
        },
        {
          'id': 2,
          'descripcion': 'Boleto de autobús',
          'monto': 2.00,
          'categoria': 'transporte',
          'fecha': '2026-10-14',
        },
        {
          'id': 3,
          'descripcion': 'Encebollado mixto',
          'monto': 6.00,
          'categoria': 'comida',
          'fecha': '2026-10-14',
        },
      ]);

      await tester.pumpWidget(
        GetMaterialApp(
          translations: AppTranslations(),
          locale: const Locale('es', 'EC'),
          home: const GastosScreen(),
        ),
      );

      // Procesar un frame sin esperar a que terminen
      // todas las animaciones de la aplicación.
      await tester.pump();

      // Verificar que los chips de filtro estén visibles.
      expect(
        find.widgetWithText(FilterChip, 'Todas'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(FilterChip, 'comida'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(FilterChip, 'transporte'),
        findsOneWidget,
      );

      // Inicialmente deben mostrarse todos los gastos.
      expect(
        find.text('Ceviche de camarón'),
        findsOneWidget,
      );
      expect(
        find.text('Boleto de autobús'),
        findsOneWidget,
      );
      expect(
        find.text('Encebollado mixto'),
        findsOneWidget,
      );

      // Seleccionar el filtro «comida».
      await tester.tap(
        find.widgetWithText(FilterChip, 'comida'),
      );
      await tester.pump();

      // Solo deben verse los gastos de comida.
      expect(
        find.text('Ceviche de camarón'),
        findsOneWidget,
      );
      expect(
        find.text('Encebollado mixto'),
        findsOneWidget,
      );
      expect(
        find.text('Boleto de autobús'),
        findsNothing,
      );

      // Volver a mostrar todos los gastos.
      await tester.tap(
        find.widgetWithText(FilterChip, 'Todas'),
      );
      await tester.pump();

      expect(
        find.text('Ceviche de camarón'),
        findsOneWidget,
      );
      expect(
        find.text('Boleto de autobús'),
        findsOneWidget,
      );
      expect(
        find.text('Encebollado mixto'),
        findsOneWidget,
      );
    },
  );
}
