import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import 'package:flutter_mailer/flutter_mailer.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'package:flutter/foundation.dart' as foundation;

import 'package:proximity_sensor/proximity_sensor.dart';

import 'package:rxdart/rxdart.dart';
import 'package:sound_stream/sound_stream.dart';
import 'package:dialogflow_grpc/dialogflow_grpc.dart';
import 'package:dialogflow_grpc/generated/google/cloud/dialogflow/v2beta1/session.pb.dart';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:convert';
import 'package:http/http.dart' as http;

import 'package:geolocator/geolocator.dart';

import 'package:flutter_background_service/flutter_background_service.dart'
    show
        AndroidConfiguration,
        FlutterBackgroundService,
        IosConfiguration,
        ServiceInstance;
import 'package:url_launcher/url_launcher.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeService();
  runApp(Chat());
}

class Chat extends StatefulWidget {
  @override
  _ChatState createState() => _ChatState();
}

class _ChatState extends State<Chat> {
  bool isPlaying = false;
  bool _isNear = false;
  late String queryText;
  late String fulfillmentText;
  FlutterTts flutterTts = FlutterTts();
  TextEditingController controller = TextEditingController();
  double volume = 1.0;
  double pitch = 1.0;
  double speechRate = 0.5;
  late String query;
  late List<String> languages;
  String langCode = "es-ES";
  var isActive = false;
  final TextEditingController _textController = TextEditingController();
  bool _isRecording = false;
  final RecorderStream _recorder = RecorderStream();

  List<double> _accelData = List.filled(3, 0.0);
  late StreamSubscription _recorderStatus;
  late StreamSubscription<List<int>> _audioStreamSubscription;
  late BehaviorSubject<List<int>> _audioStream;
  late StreamSubscription<dynamic> _streamSubscription;
  String dialogo = '';
  // TODO DialogflowGrpc class instance
  late DialogflowGrpcV2Beta1 dialogflow;
  //sensor to proximity

  @override
  void initState() {
    initializeTts();
    initPlugin();
    //_setupClient();
    listenSensor();
    _speak("Hola y bienvenido, soy tu asistente Ecco, ¿En qué puedo ayudarte?");
    super.initState();
  }

  @override
  void dispose() {
    _recorderStatus.cancel();
    _audioStreamSubscription.cancel();
    _streamSubscription.cancel();
    flutterTts.stop();
    super.dispose();
  }

  //PARTE IMPORTANTE DEL SENSOR
  void listenSensor() {
    FlutterError.onError = (FlutterErrorDetails details) {
      if (foundation.kDebugMode) {
        FlutterError.dumpErrorToConsole(details);
      }
    };
    _streamSubscription = ProximitySensor.events.listen((int event) {
      setState(() {
        event > 0 ? _isNear = true : _isNear = false;
        if ((_isNear)) {
          hablar();
          print("esta tocando");
          _isRecording = true;
        } else {
          escuchar();
          _isRecording = false;
        }
      });
    });
  }

  Future hablar() async {
    await stopStream;
    print("se activo hablar");
  }

  Future escuchar() async {
    await handleStream;
    print("se activo escuchar");
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> initPlugin() async {
    print("paso por aqui init plugin ");
    languages = List<String>.from(await flutterTts.getLanguages);
    _recorderStatus = _recorder.status.listen((status) {
      if (mounted) {
        setState(() {
          _isRecording = status == SoundStreamStatus.Playing;
        });
      }
    });

    await Future.wait([_recorder.initialize()]);
    final serviceAccount = ServiceAccount.fromString(
        '${(await rootBundle.loadString('assets/credentials.json'))}');
    // Create a DialogflowGrpc Instance
    dialogflow = DialogflowGrpcV2Beta1.viaServiceAccount(serviceAccount);
  }

  void stopStream() async {
    print("stopStream");
    await _recorder.stop();
    await _audioStreamSubscription.cancel();
    await _audioStream.close();
    _stop();
  }

  void handleSubmitted(text) async {
    print("handle submitted $text");
    _textController.clear();
    DetectIntentResponse data = await dialogflow.detectIntent(text, 'es-ES');
    String fulfillmentText = data.queryResult.fulfillmentText;
  }

  void handleStream() async {
    print("se activo handlestream");
    _recorder.start();
    _audioStream = BehaviorSubject<List<int>>();
    _audioStreamSubscription = _recorder.audioStream.listen((data) {
      print("data $data");
      _audioStream.add(data);
    });

    var biasList = SpeechContextV2Beta1(phrases: [
      'Dialogflow CX',
      'Dialogflow Essentials',
      'Action Builder',
      'HIPAA'
    ], boost: 20.0);

    var config = InputConfigV2beta1(
        encoding: 'AUDIO_ENCODING_LINEAR_16',
        languageCode: 'es-ES',
        sampleRateHertz: 16000,
        singleUtterance: false,
        speechContexts: [biasList]);
    final responseStream =
        dialogflow.streamingDetectIntent(config, _audioStream);
    responseStream.listen((data) {
      //print('----');
      setState(() {
        String transcript = data.recognitionResult.transcript;
        queryText = data.queryResult.queryText;
        fulfillmentText = data.queryResult.fulfillmentText;
        print("fullfilment text  $fulfillmentText");
        print("este es el querytext $queryText");

        actions(fulfillmentText);
        //actionLugares();
        if (fulfillmentText.isNotEmpty) {
          controller.text = fulfillmentText;
        }
        if (transcript.isNotEmpty) {
          _textController.text = transcript;
        }
      });
    }, onError: (e) {
      //print(e);
    }, onDone: () {
      _speak(controller.text);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
          appBar: AppBar(
            title: Text('Ecco Voz'),
          ),
          body: Column(
            children: <Widget>[
              Container(
                  decoration: BoxDecoration(color: Theme.of(context).cardColor),
                  child: IconTheme(
                    data: IconThemeData(color: Theme.of(context).accentColor),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Row(
                        children: <Widget>[
                          IconButton(
                            alignment: Alignment.centerRight,
                            iconSize: 320.0,
                            icon:
                                Icon(_isRecording ? Icons.mic_off : Icons.mic),
                            onPressed: _isRecording ? stopStream : handleStream,
                          ),
                        ],
                      ),
                    ),
                  )),
              Column(
                children: <Widget>[
                  Center(
                    child: Text('proximity sensor, is near ?  $_isNear\n'),
                  ),
                ],
              ),
            ],
          )),
    );
  }

  initializeTts() {
    flutterTts = FlutterTts();
    initSetting();
  }

  void initSetting() async {
    await flutterTts.setVolume(volume);
    await flutterTts.setPitch(pitch);
    await flutterTts.setSpeechRate(speechRate);
    await flutterTts.setLanguage(langCode);
  }

  void _speak(String mensaje, [bool awaitCompletion = false]) async {
    if (mensaje != null && mensaje.isNotEmpty) {
      var debug = await flutterTts.speak(mensaje);
      if (debug == 1) {
        setState(() {
          print(isPlaying);
          isPlaying = true;
        });
      }
      if (awaitCompletion) {
        await flutterTts.awaitSpeakCompletion(true);
      }
    }
  }

  void _stop() async {
    var res = await flutterTts.stop();
    if (res == 1) {
      setState(() {
        isPlaying = false;
      });
    }
  }

  actions(String text) async {
    String _lugarActual = '';
    String _listaLugares = "";
    String dialogo;
    print(text);
    if (text == 'ubicación') {
      dialogo = 'tu ubicación actual es:';
      Position position = await _determinePosition();
      final double latitude = position.latitude;
      final double longitude = position.longitude;
      print('Latitude: $latitude, Longitude: $longitude');
      //TODO integracion con google maps
      String apiKey = "AIzaSyCICIf6fafx5Jil1UFsZz22CRg1GCPJ7-M";
      List<dynamic> places;
      double lat = latitude;
      double lng = longitude;
      String url =
          'https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=$lat,$lng&radius=100&key=$apiKey';

      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        Map<String, dynamic> data = json.decode(response.body);
        print("data: $data");
        places = data['results'];
        String lugar = '';
        _lugarActual = places[places.length - 1]['name'];
        _lugarActual += places[0]['name'];

        dialogo += _lugarActual;
        if (_listaLugares.length < 1) {
          _speak('No encontré lugares cercanos...');
        }
      } else {
        _speak('Error al obtener la ubicación...');
      }
      _speak(dialogo);
    }
    if (text == 'lugares') {
      Position position = await _determinePosition();
      final double latitude = position.latitude;
      final double longitude = position.longitude;
      //TODO integracion con google maps
      String apiKey = "AIzaSyCICIf6fafx5Jil1UFsZz22CRg1GCPJ7-M";
      List<dynamic> places;
      double lat = latitude;
      double lng = longitude;
      String url =
          'https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=$lat,$lng&radius=120&key=$apiKey';
      _speak('Los lugares cercanos a tu alrededor son:');
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        Map<String, dynamic> data = json.decode(response.body);
        print("data: $data");
        places = data['results'];
        String lugar = '';
        _lugarActual = places[places.length - 1]['name'];

        for (var i = 0; i < places.length; i++) {
          print('data: ' + places[i].toString());
          String place = places[i]['name'];
          _listaLugares += '${place.toLowerCase()}, ';
        }
        _speak(_listaLugares);
      }
    }
    if (text == 'enviar') {
      dialogo = 'Compartiendo tu ubicación';
      _speak(dialogo);

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final double latitude = position.latitude;
      final double longitude = position.longitude;

      print('Latitude: $latitude, Longitude: $longitude');

      final url3 =
          "https://wa.me/59172230940?text=Estoy%20en%20camino.%20Consulta%20mi%20Ubicacion%20En%20este%20enlace%20de%20Google%20Maps:%20https://www.google.com/maps?q=$latitude,$longitude";
      //await launch(url3)

      final MailOptions mailOptions = MailOptions(
        body:
            'Estoy en camino. Consulta mi Ubicacion En este enlace de Google Maps: $url3',
        subject: 'the Email Subject',
        recipients: ['acblanco837@gmail.com'],
        isHTML: true,
        bccRecipients: ['other@example.com'],
        ccRecipients: ['third@example.com'],
        attachments: [
          'path/to/image.png',
        ],
      );
      String platformResponse;
      try {
        final MailerResponse response = await FlutterMailer.send(mailOptions);
        switch (response) {
          case MailerResponse.android:
            platformResponse = 'intent was successful';
            break;
          default:
            platformResponse = 'unknown';
            break;
        }
      } on PlatformException catch (error) {
        platformResponse = error.toString();
        print(error);
        if (!mounted) {
          return;
        }
        await showDialog<void>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            content: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'Message',
                  style: Theme.of(context).textTheme.subtitle1,
                ),
                Text(error.message ?? 'unknown error'),
              ],
            ),
            contentPadding: const EdgeInsets.all(26),
            title: Text(error.code),
          ),
        );
      } catch (error) {
        platformResponse = error.toString();
      }
      _speak('Tu ubicacion ha sido enviada correctamente');
    }
    if (queryText.contains("llegar")) {
      if (fulfillmentText != "Repite el dato de destino") {
        String destino = fulfillmentText;
        Position position = await _determinePosition();
        final double latitude = position.latitude;
        final double longitude = position.longitude;
        String origen = "$latitude,$longitude";
        String apiKey = "AIzaSyCICIf6fafx5Jil1UFsZz22CRg1GCPJ7-M";
        List<dynamic> places;
        double lat = latitude;
        double lng = longitude;
        String indicaciones = "";
        String paso;
        String url =
            'https://maps.googleapis.com/maps/api/directions/json?destination=$destino&origin=$origen&mode=walking&language=es-ES&key=$apiKey';
        final response = await http.get(Uri.parse(url));
        if (response.statusCode == 200) {
          Map<String, dynamic> data = json.decode(response.body);
          //print("data: $data['routes']['steps'] ");
          try {
            places = data['routes'][0]['legs'][0]['steps'];
            for (int i = 0; i < places.length; i++) {
              int distancia = places[i]['distance']['value'];
              String paso = places[i]['html_instructions']
                  .replaceAll(RegExp(r'<[^>]*>|&[^;]+;'), ' ');
              paso.replaceAll('1', ' ') ;
              indicaciones += "paso $i: $paso , $distancia metros, ";
            }
            print(indicaciones);
          } catch (error) {
            print(error);
            _speak("Lugar no encontrado");
          }
        }

        print('origen y destino: $destino $origen');
        _speak(indicaciones);
      }
    }
  }
}

Future<Position> _determinePosition() async {
  bool serviceEnabled;
  LocationPermission permission;

  // Test if location services are enabled.
  serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    // Location services are not enabled don't continue
    // accessing the position and request users of the
    // App to enable the location services.
    return Future.error('Location services are disabled.');
  }

  permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      // Permissions are denied, next time you could try
      // requesting permissions again (this is also where
      // Android's shouldShowRequestPermissionRationale
      // returned true. According to Android guidelines
      // your App should show an explanatory UI now.
      return Future.error('Location permissions are denied');
    }
  }

  if (permission == LocationPermission.deniedForever) {
    // Permissions are denied forever, handle appropriately.
    return Future.error(
        'Location permissions are permanently denied, we cannot request permissions.');
  }

  // When we reach here, permissions are granted and we can
  // continue accessing the position of the device.
  return await Geolocator.getCurrentPosition(
    desiredAccuracy: LocationAccuracy.high,
  );
}

//AQUI TENEMOS LA PARTE DEL SEGUNDO PLANO BACKGROUND
Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  /// OPTIONAL, using custom notification channel id
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'my_foreground', // id
    'MY FOREGROUND SERVICE', // title
    description:
        'This channel is used for important notifications.', // description
    importance: Importance.low, // importance must be at low or higher level
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      // this will be executed when app is in foreground or background in separated isolate
      onStart: onStart,

      // auto start service
      autoStart: true,
      isForegroundMode: true,

      notificationChannelId: 'my_foreground',
      initialNotificationTitle: 'Ecco Service',
      initialNotificationContent: 'Initializing',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      // auto start service
      autoStart: true,

      // this will be executed when app is in foreground in separated isolate
      onForeground: onStart,

      // you have to enable background fetch capability on xcode project
      onBackground: onIosBackground,
    ),
  );

  service.startService();
}

// to ensure this is executed
// run app from xcode, then from xcode menu, select Simulate Background Fetch

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  SharedPreferences preferences = await SharedPreferences.getInstance();
  await preferences.reload();
  final log = preferences.getStringList('log') ?? <String>[];
  log.add(DateTime.now().toIso8601String());
  await preferences.setStringList('log', log);

  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // Only available for flutter 3.0.0 and later
  DartPluginRegistrant.ensureInitialized();

  // For flutter prior to version 3.0.0
  // We have to register the plugin manually

  SharedPreferences preferences = await SharedPreferences.getInstance();
  await preferences.setString("hello", "world");

  /// OPTIONAL when use custom notification
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // bring to foreground
  Timer.periodic(const Duration(seconds: 1), (timer) async {
    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        /// OPTIONAL for use custom notification
        /// the notification id must be equals with AndroidConfiguration when you call configure() method.
        flutterLocalNotificationsPlugin.show(
          888,
          'COOL SERVICE',
          'Awesome ${DateTime.now()}',
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'my_foreground',
              'MY FOREGROUND SERVICE',
              icon: 'ic_bg_service_small',
              ongoing: true,
            ),
          ),
        );

        // if you don't using custom notification, uncomment this
        // service.setForegroundNotificationInfo(
        //   title: "My App Service",
        //   content: "Updated at ${DateTime.now()}",
        // );
      }
    }

    /// you can see this log in logcat
    //print('FLUTTER BACKGROUND SERVICE: ${DateTime.now()}');

    // test using external plugin
    final deviceInfo = DeviceInfoPlugin();
    String? device;
    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      device = androidInfo.model;
    }
    service.invoke(
      'update',
      {
        "current_date": DateTime.now().toIso8601String(),
        "device": device,
      },
    );
  });
}

mixin DartPluginRegistrant {
  static void ensureInitialized() {}
}

class LogView extends StatefulWidget {
  const LogView({Key? key}) : super(key: key);

  @override
  State<LogView> createState() => _LogViewState();
}

class _LogViewState extends State<LogView> {
  late final Timer timer;
  List<String> logs = [];

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      final SharedPreferences sp = await SharedPreferences.getInstance();
      await sp.reload();
      logs = sp.getStringList('log') ?? [];
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: logs.length,
      itemBuilder: (context, index) {
        final log = logs.elementAt(index);
        return Text(log);
      },
    );
  }
}
