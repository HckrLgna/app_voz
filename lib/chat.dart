import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'package:flutter/foundation.dart' as foundation;
import 'package:gplaces/gplaces.dart';
import 'package:proximity_sensor/proximity_sensor.dart';

import 'package:rxdart/rxdart.dart';
import 'package:sound_stream/sound_stream.dart';
import 'package:dialogflow_grpc/dialogflow_grpc.dart';
import 'package:dialogflow_grpc/generated/google/cloud/dialogflow/v2beta1/session.pb.dart';

class Chat extends StatefulWidget {
  @override
  _ChatState createState() => _ChatState();
}

class _ChatState extends State<Chat> {
  FlutterTts flutterTts = FlutterTts();
  TextEditingController controller = TextEditingController();
  double volume = 1.0;
  double pitch = 1.0;
  double speechRate = 0.5;
  List<String> languages;
  String langCode = "es-ES";
  var isActive = false;
  final TextEditingController _textController = TextEditingController();
  bool _isRecording = false;
  final RecorderStream _recorder = RecorderStream();

  List<double> _accelData = List.filled(3, 0.0);
  StreamSubscription _recorderStatus;
  StreamSubscription<List<int>> _audioStreamSubscription;
  BehaviorSubject<List<int>> _audioStream;
  StreamSubscription<dynamic> _streamSubscription;

  // TODO DialogflowGrpc class instance
  DialogflowGrpcV2Beta1 dialogflow;
  //sensor to proximity
  bool _isNear = false;

  final List<AutocompletePrediction> _autocompletePredictions = [];
  final List<PlaceLikelihood> _placeLikelihoods = [];
  PlacesClient _placesClient;

  @override
  void initState() {
    super.initState();
    listenSensor();
    initPlugin();
    _setupClient();
  }

  @override
  void dispose() {
    _recorderStatus.cancel();
    _audioStreamSubscription.cancel();
    _streamSubscription.cancel();
    super.dispose();
  }

  //sensor
  Future<void> listenSensor() async {
    FlutterError.onError = (FlutterErrorDetails details) {
      if (foundation.kDebugMode) {
        FlutterError.dumpErrorToConsole(details);
      }
    };
    _streamSubscription = ProximitySensor.events.listen((int event) {
      setState(() {
        if ((event > 0)) {
          _isNear = true;
          handleStream;
          print("esta tocando");
        } else {
          _isNear = false;
          stopStream;
        }
      });
    });
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
    await _recorder.stop();
    await _audioStreamSubscription.cancel();
    await _audioStream.close();
    await _stop();
  }

  void handleSubmitted(text) async {
    print("text $text");
    _textController.clear();
    DetectIntentResponse data = await dialogflow.detectIntent(text, 'es-ES');
    String fulfillmentText = data.queryResult.fulfillmentText;
  }

  void handleStream() async {
    print("se activo handlestream");
    _recorder.start();
    _audioStream = BehaviorSubject<List<int>>();
    _audioStreamSubscription = _recorder.audioStream.listen((data) {
      //print("data $data");
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
        String queryText = data.queryResult.queryText;
        String fulfillmentText = data.queryResult.fulfillmentText;
        print("fullfilment text  $fulfillmentText");
        if (fulfillmentText.isNotEmpty) {
          controller.text = fulfillmentText;
          if (fulfillmentText.contains("0")) {
            flutterTts.speak(
                "te encuentras en: ${_autocompletePredictions[0].description}");
            print(
                "te encuentras en: ${_autocompletePredictions[0].description}");
          }
          if (fulfillmentText.contains("lugares")) {
            for (var i in _placeLikelihoods) {
              flutterTts.speak("${_autocompletePredictions[1].description}");
            }
          }
          print(controller.text);
          _speak();
        }
        if (transcript.isNotEmpty) {
          _textController.text = transcript;
        }
      });
    }, onError: (e) {
      //print(e);
    }, onDone: () {});
  }

  // The chat interface
  //
  //------------------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Column(
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
                      icon: Icon(_isRecording ? Icons.mic_off : Icons.mic),
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
    );
  }

  void initSetting() async {
    await flutterTts.setVolume(volume);
    await flutterTts.setPitch(pitch);
    await flutterTts.setSpeechRate(speechRate);
    await flutterTts.setLanguage(langCode);
  }

  void _speak() async {
    initSetting();
    await flutterTts.speak(controller.text);
    print("esta hablando $controller.text");
  }

  void _stop() async {
    await flutterTts.stop();
  }

  Future fetchAutocompletePredictions() async {
    if (await Places.isInitialized) {
      final request = FindAutocompletePredictionsRequest(
        query: 'UAGRM',
        countries: ["bol"],
        origin: LatLng(latitude: -17.838032, longitude: -63.0964934),
        locationBias: LocationBias(
          southwest: LatLng(latitude: -33.880490, longitude: 151.184363),
          northeast: LatLng(latitude: -33.858754, longitude: 151.229596),
        ),
      );
      _placesClient
          .findAutoCompletePredictions(request: request)
          .then((response) {
        setState(() {
          _autocompletePredictions
              .addAll(response?.autocompletePredictions ?? []);
        });
      });
    }
  }

  Future findCurrentPlace() async {
    if (await Places.isInitialized) {
      final request = FindCurrentPlaceRequest(
          placeFields: [Field.ADDRESS, Field.PHOTO_METADATAS, Field.ID]);
      _placesClient.findCurrentPlace(request: request).then((response) {
        setState(() {
          _placeLikelihoods.addAll(response?.placeLikelihoods ?? []);
        });
      });
    }
  }

  Future _setupClient() async {
    await Places.initialize(showLogs: true);
    _placesClient = Places.createClient();
    fetchAutocompletePredictions();
    findCurrentPlace();
  }
}
