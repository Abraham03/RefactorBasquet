import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/core/scoreboard/scoreboard_broadcaster.dart';
import 'package:myapp/core/scoreboard/scoreboard_payload.dart';
import 'package:myapp/core/scoreboard/scoreboard_transport.dart';
import 'package:myapp/logic/match_game_controller.dart';

class _FakePublisher implements ScoreboardPublisher {
  final List<ScoreboardPayload> published = [];
  int clearCount = 0;
  bool started = false;

  @override
  Future<void> start() async => started = true;

  @override
  void publish(ScoreboardPayload payload) => published.add(payload);

  @override
  void clear() => clearCount++;

  @override
  Future<void> stop() async {}

  @override
  Stream<PublisherStatus> get status => const Stream.empty();

  @override
  PublisherStatus get currentStatus => const PublisherStatus.stopped();
}

void main() {
  const meta = ScoreboardMeta(teamAName: 'Lobos', teamBName: 'Águilas');

  /// Deja pasar la ventana de coalescing de 50 ms.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 120));

  test('no difunde nada mientras no haya partido abierto', () async {
    final publisher = _FakePublisher();
    final broadcaster = ScoreboardBroadcaster(publisher);

    broadcaster.onState(const MatchState(scoreA: 5));
    await settle();

    expect(publisher.published, isEmpty);
    broadcaster.dispose();
  });

  test('difunde en cuanto se declara el partido', () async {
    final publisher = _FakePublisher();
    final broadcaster = ScoreboardBroadcaster(publisher);

    broadcaster.onState(const MatchState(scoreA: 5, scoreB: 3));
    broadcaster.onMeta(meta);
    await settle();

    expect(publisher.published.length, 1);
    expect(publisher.published.single.state.scoreA, 5);
    expect(publisher.published.single.teamAName, 'Lobos');
    broadcaster.dispose();
  });

  test('agrupa una ráfaga de cambios en una sola emisión', () async {
    final publisher = _FakePublisher();
    final broadcaster = ScoreboardBroadcaster(publisher);
    broadcaster.onMeta(meta);
    await settle();
    publisher.published.clear();

    for (var i = 1; i <= 10; i++) {
      broadcaster.onState(MatchState(scoreA: i));
    }
    await settle();

    expect(publisher.published.length, 1, reason: 'coalescing de 50 ms');
    expect(publisher.published.single.state.scoreA, 10,
        reason: 'gana el último estado');
    broadcaster.dispose();
  });

  test('cerrar el partido limpia el marcador difundido', () async {
    final publisher = _FakePublisher();
    final broadcaster = ScoreboardBroadcaster(publisher);
    broadcaster.onMeta(meta);
    broadcaster.onState(const MatchState(scoreA: 20));
    await settle();

    broadcaster.onMeta(null);
    await settle();

    expect(publisher.clearCount, 1);

    // Un estado posterior no debe reactivar la difusión.
    broadcaster.onState(const MatchState(scoreA: 99));
    await settle();
    expect(publisher.published.every((p) => p.state.scoreA != 99), isTrue);

    broadcaster.dispose();
  });

  test('dispose detiene emisiones pendientes', () async {
    final publisher = _FakePublisher();
    final broadcaster = ScoreboardBroadcaster(publisher);
    broadcaster.onMeta(meta);
    await settle();
    publisher.published.clear();

    broadcaster.onState(const MatchState(scoreA: 7));
    broadcaster.dispose();
    await settle();

    expect(publisher.published, isEmpty);
  });
}
