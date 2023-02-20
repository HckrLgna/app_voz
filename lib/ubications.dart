import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gplaces/gplaces.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final List<AutocompletePrediction> _autocompletePredictions = [];
  final List<PlaceLikelihood> _placeLikelihoods = [];
  PlacesClient _placesClient;

  @override
  void initState() {
    _setupClient();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(
          title: const Text('gplaces'),
        ),
        body: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  ListView.separated(
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                            "${_autocompletePredictions[index].description}"),
                      );
                    },
                    itemCount: _autocompletePredictions.length,
                    separatorBuilder: (context, index) {
                      return const Divider();
                    },
                  ),
                  ListView.separated(
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                            "(${_placeLikelihoods[index].likelihood?.toStringAsFixed(2)}): ${_placeLikelihoods[index].place?.address}"),
                      );
                    },
                    itemCount: _placeLikelihoods.length,
                    separatorBuilder: (context, index) {
                      return const Divider();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future fetchAutocompletePredictions() async {
    if (await Places.isInitialized) {
      final request = FindAutocompletePredictionsRequest(
        query: 'Plan3000',
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

  Future<FetchPlaceResponse> fetchPlace(String placeId) async {
    if (await Places.isInitialized) {
      final request = FetchPlaceRequest(
        placeId: placeId,
        placeFields: [Field.PHOTO_METADATAS],
      );

      return _placesClient.fetchPlace(request: request);
    }

    return null;
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
    fetchPlace("ChIJHZyasTQBoDkRj53m5ZpLdSM");
    fetchAutocompletePredictions();
    findCurrentPlace();
  }
}
