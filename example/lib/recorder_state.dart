import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_sound/flauto.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart' show getTemporaryDirectory;
import 'package:flutter_sound/flutter_sound_recorder.dart';
import 'active_codec.dart';
import 'common.dart';
import 'main.dart';
import 'media_path.dart';
import 'player_state.dart';

class RecorderState {
  static const _durationInterval = 1.0;
  static final RecorderState _self = RecorderState._internal();
  StreamSubscription _recorderSubscription;
  StreamSubscription _dbPeakSubscription;
  FlutterSoundRecorder recorderModule;
  FlutterSoundRecorder recorderModule_2; // Used if REENTRANCE_CONCURENCY

  final StreamController<double> _durationController =
      StreamController<double>.broadcast();
  StreamController<double> dbLevelController =
      StreamController<double>.broadcast();

  factory RecorderState() {
    return _self;
  }

  RecorderState._internal();
  bool get isRecording => recorderModule != null && recorderModule.isRecording;
  bool get isPaused => recorderModule != null && recorderModule.isPaused;

  void init() async {
    recorderModule = await FlutterSoundRecorder().initialize();
    await recorderModule.setSubscriptionDuration(_durationInterval);
    await recorderModule.setDbPeakLevelUpdate(0.8);
    await recorderModule.setDbLevelEnabled(true);
    if (renetranceConcurrency) {
      recorderModule_2 = await FlutterSoundRecorder().initialize();
      await recorderModule_2.setSubscriptionDuration(_durationInterval);
      await recorderModule_2.setDbPeakLevelUpdate(0.8);
      await recorderModule_2.setDbLevelEnabled(true);
    }
    ActiveCodec().recorderModule = recorderModule;
  }

  void reset() async {
    await recorderModule.setSubscriptionDuration(_durationInterval);

    if (renetranceConcurrency) {
      await recorderModule_2.setSubscriptionDuration(_durationInterval);
    }

    // cause the recording UI to refesh and update with
    // any state changes.
    await RecorderState().stopRecorder();
  }

  Stream<double> get durationStream {
    return _durationController.stream;
  }

  Stream<double> get dbLevelStream {
    return dbLevelController.stream;
  }

  void stopRecorder() async {
    try {
      var result = await recorderModule.stopRecorder();
      print('stopRecorder: $result');
      cancelRecorderSubscriptions();
      if (renetranceConcurrency) {
        await recorderModule_2.stopRecorder();
        await PlayerState().stopPlayer();
      }
    } catch (err) {
      print('stopRecorder error: $err');
    }
  }

  void startRecorder(BuildContext context) async {
    try {
      await PlayerState().stopPlayer();
      var tempDir = await getTemporaryDirectory();

      var path = await recorderModule.startRecorder(
        uri:
            '${tempDir.path}/${recorderModule.slotNo}-${MediaPath.paths[ActiveCodec().codec.index]}',
        codec: ActiveCodec().codec,
      );

      print('startRecorder: $path');

      trackDuration();
      trackDBLevel();
      if (renetranceConcurrency) {
        try {
          var dataBuffer =
              (await rootBundle.load(assetSample[ActiveCodec().codec.index]))
                  .buffer
                  .asUint8List();
          await PlayerState().playerModule_2.startPlayerFromBuffer(dataBuffer,
              codec: ActiveCodec().codec, whenFinished: () {
            print('Secondary Play finished');
          });
        } catch (e) {
          print('startRecorder error: $e');
          rethrow;
        }
        await recorderModule_2.startRecorder(
          uri: '${tempDir.path}/flutter_sound_recorder2.aac',
          codec: t_CODEC.CODEC_AAC,
        );
        print(
            "Secondary record is '${tempDir.path}/flutter_sound_recorder2.aac'");
      }

      MediaPath().setCodecPath(ActiveCodec().codec, path);
    } on RecorderException catch (err) {
      print('startRecorder error: $err');

      var error = SnackBar(
          backgroundColor: Colors.red,
          content: Text('Failed to start recording: ${err.message}'));
      Scaffold.of(context).showSnackBar(error);

      stopRecorder();
    }
  }

  void trackDBLevel() {
    _dbPeakSubscription =
        recorderModule.onRecorderDbPeakChanged.listen((value) {
      print("got dbLevel update -> $value");

      dbLevelController.add(value);
    });
  }

  void trackDuration() {
    _recorderSubscription = recorderModule.onRecorderStateChanged.listen((e) {
      if (e != null && e.currentPosition != null) {
        var duration = e.currentPosition;
        // print("got duration update -> $duration");
        _durationController.add(duration);
      }
    });
  }

  void pauseResumeRecorder() {
    if (recorderModule.isPaused) {
      {
        recorderModule.resumeRecorder();
        if (renetranceConcurrency) {
          recorderModule_2.resumeRecorder();
        }
      }
    } else {
      recorderModule.pauseRecorder();
      if (renetranceConcurrency) {
        recorderModule_2.pauseRecorder();
      }
    }
  }

  void cancelRecorderSubscriptions() {
    if (_recorderSubscription != null) {
      _recorderSubscription.cancel();
      _recorderSubscription = null;
    }
    if (_dbPeakSubscription != null) {
      _dbPeakSubscription.cancel();
      _dbPeakSubscription = null;
    }
  }

  void release() async {
    await recorderModule.release();
    await recorderModule_2.release();
  }
}
