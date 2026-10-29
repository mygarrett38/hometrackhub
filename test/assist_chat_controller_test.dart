import 'package:flutter_test/flutter_test.dart';
import 'package:hometrackhub/data/assist_chat_repository.dart';
import 'package:hometrackhub/models/assist_chat.dart';
import 'package:hometrackhub/state/assist_chat_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences preferences;
  late DateTime now;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    now = DateTime(2026, 10, 1, 9);
  });

  AssistChatController createController() =>
      AssistChatController(AssistChatRepository(preferences), clock: () => now);

  test('saved chats are loaded again on the next launch', () async {
    final controller = createController();
    final id = await controller.startChat('Why is my sink slow?');
    await controller.addMessage(
      id,
      const AssistChatMessage.assistant(
        'Clean the P-trap.',
        professionalNote: 'Call a plumber if it keeps clogging.',
      ),
    );
    await controller.rename(id, 'Kitchen sink');

    final reloaded = createController();
    final chat = reloaded.chats.single;

    expect(reloaded.titleOf(chat), 'Kitchen sink');
    expect(
      [for (final message in chat.messages) message.content],
      ['Why is my sink slow?', 'Clean the P-trap.'],
    );
    expect(
      chat.messages.last.professionalNote,
      'Call a plumber if it keeps clogging.',
    );
  });

  test('chats are listed most recently active first', () async {
    final controller = createController();
    final older = await controller.startChat('First question');
    now = now.add(const Duration(hours: 1));
    final newer = await controller.startChat('Second question');
    now = now.add(const Duration(hours: 1));
    await controller.addMessage(older, const AssistChatMessage.user('More'));

    expect([for (final chat in controller.chats) chat.id], [older, newer]);
  });

  test('a chat expires 14 days after its last message', () async {
    final controller = createController();
    final id = await controller.startChat('Furnace filter?');

    now = now.add(const Duration(days: 10));
    await controller.addMessage(id, const AssistChatMessage.user('Still?'));

    // Fourteen days from the first message, but only four from the last.
    now = now.add(const Duration(days: 4));
    expect(controller.chatById(id), isNotNull);

    now = now.add(const Duration(days: 10));
    expect(controller.chats, isEmpty);
    expect(controller.chatById(id), isNull);
  });

  test('renaming a chat does not keep it from expiring', () async {
    final controller = createController();
    final id = await controller.startChat('Furnace filter?');

    now = now.add(const Duration(days: 13));
    await controller.rename(id, 'Furnace');
    now = now.add(const Duration(days: 1));

    expect(controller.chats, isEmpty);
  });

  test(
    'expired chats are deleted from the device on the next launch',
    () async {
      await createController().startChat('Furnace filter?');
      now = now.add(const Duration(days: 15));

      createController();
      // The deletion is saved without waiting, so let it finish.
      await Future<void>.delayed(Duration.zero);

      expect(AssistChatRepository(preferences).load(), isEmpty);
    },
  );

  test('a chat is named after the day it was started', () async {
    final controller = createController();
    String titleOf(String id) => controller.titleOf(controller.chatById(id)!);

    final first = await controller.startChat('Furnace filter?');
    expect(titleOf(first), 'October 1st Chat');

    // Once there's another chat that day, the first one shows its number.
    now = now.add(const Duration(hours: 2));
    final second = await controller.startChat('Dryer vent?');
    now = now.add(const Duration(hours: 2));
    final third = await controller.startChat('Gutters?');
    expect(titleOf(first), 'October 1st Chat 1');
    expect(titleOf(second), 'October 1st Chat 2');
    expect(titleOf(third), 'October 1st Chat 3');

    // A chat on another day is numbered on its own.
    now = DateTime(2026, 10, 2, 8);
    final nextDay = await controller.startChat('Smoke alarm?');
    expect(titleOf(nextDay), 'October 2nd Chat');

    // A renamed chat keeps its name, and the others keep their numbers.
    await controller.rename(second, 'Dryer');
    expect(titleOf(second), 'Dryer');
    expect(titleOf(third), 'October 1st Chat 3');
  });

  test('numbers never change once a chat has one', () async {
    final controller = createController();
    String titleOf(String id) => controller.titleOf(controller.chatById(id)!);

    final first = await controller.startChat('One');
    final second = await controller.startChat('Two');
    final third = await controller.startChat('Three');

    // Deleting an earlier chat leaves a gap rather than renumbering.
    await controller.delete(second);
    expect(titleOf(first), 'October 1st Chat 1');
    expect(titleOf(third), 'October 1st Chat 3');
    final fourth = await controller.startChat('Four');
    expect(titleOf(fourth), 'October 1st Chat 4');

    // Deleting the most recent chat frees its number for the next one.
    await controller.delete(fourth);
    final replacement = await controller.startChat('Four again');
    expect(titleOf(replacement), 'October 1st Chat 4');

    // A chat keeps its number even once it's the only one left that day.
    await controller.delete(first);
    await controller.delete(replacement);
    expect(titleOf(third), 'October 1st Chat 3');

    // Numbers are saved, so they're the same on the next launch.
    final reloaded = createController();
    expect(reloaded.titleOf(reloaded.chatById(third)!), 'October 1st Chat 3');
  });

  test('an empty or unchanged name goes back to the default name', () async {
    final controller = createController();
    final id = await controller.startChat('How do I clean a dryer vent?');
    String title() => controller.titleOf(controller.chatById(id)!);

    await controller.rename(id, 'Dryer');
    expect(title(), 'Dryer');

    await controller.rename(id, '   ');
    expect(title(), 'October 1st Chat');
    expect(controller.chatById(id)!.name, isNull);

    // Saving the default name as it is doesn't fix it, so it still gets a
    // number once there's another chat that day.
    await controller.rename(id, 'October 1st Chat');
    expect(controller.chatById(id)!.name, isNull);
    await controller.startChat('Another question');
    expect(title(), 'October 1st Chat 1');
  });

  test('deleting chats removes them from the device', () async {
    final controller = createController();
    final kept = await controller.startChat('Keep me');
    final deleted = await controller.startChat('Delete me');

    await controller.delete(deleted);
    expect([for (final chat in createController().chats) chat.id], [kept]);

    await controller.deleteAll();
    expect(createController().chats, isEmpty);
  });

  test('an answer for a deleted chat is dropped', () async {
    final controller = createController();
    final id = await controller.startChat('Question');
    await controller.delete(id);

    await controller.addMessage(
      id,
      const AssistChatMessage.assistant('Answer'),
    );

    expect(controller.chats, isEmpty);
  });

  group('AssistChat', () {
    AssistChat chatWith(List<AssistChatMessage> messages) => AssistChat(
      id: 'chat',
      messages: messages,
      createdAt: DateTime(2026, 10, 1),
      lastActiveAt: DateTime(2026, 10, 1),
      dayNumber: 1,
    );

    test('only the end of a long chat is sent, starting with a question', () {
      final messages = [
        for (var i = 0; i < 29; i++)
          i.isEven
              ? AssistChatMessage.user('Question $i')
              : AssistChatMessage.assistant('Answer $i'),
      ];
      final sent = chatWith(messages).recentMessages();

      expect(sent.length, lessThanOrEqualTo(AssistChat.maxMessagesSent));
      expect(sent.first.role, 'user');
      expect(sent.last.content, 'Question 28');
    });

    test('earlier messages are left out once they are too long to send', () {
      final long = 'x' * (AssistChat.maxCharactersSent - 10);
      final sent = chatWith([
        const AssistChatMessage.user('First question'),
        AssistChatMessage.assistant(long),
        const AssistChatMessage.user('Follow-up'),
      ]).recentMessages();

      expect([for (final message in sent) message.content], ['Follow-up']);
    });
  });
}
