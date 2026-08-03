// Idée #36 : « l'espace du clavier devient vide ». Un inset IME resté
// appliqué après la perte du focus réserve une bande vide en bas de l'écran
// (contenu comprimé, seule la barre du bas paraît normale). On vérifie ici
// les deux garde-fous : fermeture explicite du clavier, et rattrapage
// automatique quand l'inset survit au champ qui l'a ouvert.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/widgets/keyboard_guard.dart';

/// Espionne le canal texte. À installer DANS le test : la liaison de test
/// réinstalle son propre gestionnaire au démarrage de chaque test.
List<String> _spyTextInput() {
  final calls = <String>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.textInput, (call) async {
    calls.add(call.method);
    return null;
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.textInput, null),
  );
  return calls;
}

void main() {
  testWidgets('dismissKeyboard retire le focus et ferme l\'IME', (
    tester,
  ) async {
    final calls = _spyTextInput();
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: TextField(focusNode: focusNode))),
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);

    dismissKeyboard();
    await tester.pump();

    expect(focusNode.hasFocus, isFalse);
    expect(calls, contains('TextInput.hide'));
  });

  testWidgets('le garde ferme un clavier resté ouvert sans champ focalisé', (
    tester,
  ) async {
    final calls = _spyTextInput();
    await tester.pumpWidget(
      const MaterialApp(
        home: KeyboardInsetGuard(child: Scaffold(body: SizedBox())),
      ),
    );

    // Le clavier s'ouvre alors qu'aucun champ n'a le focus : c'est l'inset
    // fantôme qui laisse la bande vide.
    calls.clear();
    tester.view.viewInsets = const FakeViewPadding(bottom: 900);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(calls, contains('TextInput.hide'));
  });

  testWidgets('le garde laisse le clavier ouvert quand un champ est focalisé', (
    tester,
  ) async {
    final calls = _spyTextInput();
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: KeyboardInsetGuard(
          child: Scaffold(body: TextField(focusNode: focusNode)),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();

    calls.clear();
    tester.view.viewInsets = const FakeViewPadding(bottom: 900);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(focusNode.hasFocus, isTrue);
    expect(calls, isNot(contains('TextInput.hide')));
  });
}
