import 'dart:core';
import 'package:RoboNurse/mqtt/state/mqtt_state.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import './robo_ui.dart';
import './custom_widgets/splash_screen.dart';

void main() {
  debugPrint = (String message, {int wrapWidth}) {};
  runApp(new MyApp());
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

final key = new GlobalKey<RoboUIState>();

class _MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: "Robo Nurse",
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          accentColor: Colors.teal[400],
        ),
        home: SplashScreen(
          seconds: 7,
          title: Text(
            "Robo Nurse",
            style: TextStyle(
                fontFamily: "Raleway",
                fontWeight: FontWeight.bold,
                fontSize: 30.0),
          ),
          image: new Image.asset('assets/icon/icon.png'),
          photoSize: 90.0,
          backgroundColor: Colors.black,
          loaderColor: Colors.tealAccent,
          navigateAfterSeconds: ChangeNotifierProvider(
            create: (_) => MQTTAppState(),
            child: RoboUI(
              key: key,
            ),
          ),
        ));
  }
}
