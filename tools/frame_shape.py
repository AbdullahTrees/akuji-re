#!/usr/bin/env python3
"""Check the frame loop, and the form wiring no behavioural test covers.

    python tools/frame_shape.py

WHY A SOURCE-SHAPE TEST

The defect this guards against was not a wrong value, it was a wrong PLACE.
Entity_UpdateAll sat inside the state dispatch, in the play arm only, so it did
not run on the title screen, during the opening, or while paused. Every
individual line was a faithful translation; the arrangement was not.

No behavioural self-test caught it, and it is worth being clear about why: all
thirteen passed both before and after the fix. They drive a session directly
and never exercise the frame loop's own structure, because that structure lives
in a TForm and needs a window. So the claim being made here - "this arm runs
before the entity update, that one after" - is a claim about arrangement, and
the test for it has to read the arrangement.

WHERE THE TABLE COMES FROM

Not from reading the code. From notes/trace_findings.md, which is a 20,304
frame capture of the real game:

    Entity_UpdateAll        20304 calls / 20304 frames   every state
    Events_SpawnNearCamera  14560 = 12347 (state 60) + 2213 (state 140)
    EventScript_Execute      2213 = every frame of state 140
    frame 1 order: Title_Init, Entity_UpdateAll, Title_MainMenu

That last line is what proves there are two dispatches rather than one: two
different state arms ran in a single frame with the entity update between
them, which a single switch cannot do.
"""

import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GM = os.path.join(REPO, 'src', 'GmMain.pas')

# Which dispatch each state's arm belongs to, from the trace.
EXPECT_PRE = {'GS_TITLE_INIT', 'GS_STAGE_BEGIN', 'GS_PLAY', 'GS_STATE_140'}
EXPECT_POST = {'GS_TITLE_MENU', 'GS_PLAYER_INIT', 'GS_PLAY_ALT', 'GS_PLAY',
               'GS_STATE_140', 'GS_PAUSE', 'GS_ENDING', 'GS_QUIT'}


def body_of(text, name):
    start = text.index('procedure TFrm_main.%s;' % name)
    end = text.index('\nend;', text.index('case GameStateValue of', start))
    return text[start:end]


def arms(body):
    return set(re.findall(r'^\s{4}(GS_[A-Z0-9_]+)\s*[,:]', body, re.M))


def main():
    text = open(GM, encoding='utf-8').read()
    bad = []

    for name in ('DispatchPre', 'DispatchPost'):
        if 'procedure TFrm_main.%s;' % name not in text:
            print('FAIL: %s is gone - the dispatch has been merged back into '
                  'one, which puts the entity update inside it again' % name)
            return 1

    got_pre, got_post = arms(body_of(text, 'DispatchPre')), \
        arms(body_of(text, 'DispatchPost'))

    for label, got, want in (('DispatchPre', got_pre, EXPECT_PRE),
                             ('DispatchPost', got_post, EXPECT_POST)):
        for extra in sorted(got - want):
            bad.append('%s has an arm for %s, which the trace shows running '
                       'on the other side of the entity update'
                       % (label, extra))
        for missing in sorted(want - got):
            bad.append('%s has no arm for %s' % (label, missing))

    # And the ordering in AppIdle: pre, then the entity update, then post.
    idle = text[text.index('procedure TFrm_main.AppIdle'):]
    idle = idle[:idle.index('\nprocedure ')]
    order = [m.group(1) for m in re.finditer(
        r'\b(DispatchPre|FSession\.TickEntities|DispatchPost)\b', idle)]
    want_order = ['DispatchPre', 'FSession.TickEntities', 'DispatchPost']
    if order != want_order:
        bad.append('AppIdle calls %s; it must call %s, in that order - the '
                   'entity update goes BETWEEN the two dispatches'
                   % (' then '.join(order) or 'none of them',
                      ' then '.join(want_order)))

    # TickEntities must not be conditional. A guard here is the original bug
    # wearing a different hat.
    seg = idle[idle.find('DispatchPre'):idle.find('DispatchPost')]
    if re.search(r'\bif\b', seg):
        bad.append('there is an `if` between DispatchPre and DispatchPost - '
                   'the entity update runs in EVERY state, unconditionally')

    # --- wiring that only a source check can see -------------------------
    #
    # Two real bugs lived here and no self-test could have caught either,
    # because both are about what GmMain CONNECTS rather than what any unit
    # computes. The units were correct and unreachable.
    #
    #   * GameStartOrLoad gates the whole of starting a game on Host.Opening,
    #     and GmMain passed a bare TStartHost whose Opening returns False
    #     unconditionally. The cutscene never ran; the story section simply did
    #     not appear. Opening.pas was right the whole time - the trace confirms
    #     its slide timings frame for frame.
    #   * PowerUp_Show's panel is dismissed by its fanfare ENDING. With no
    #     fanfare started, the dismiss test was applied to the looping stage
    #     music, which never stops, so collecting the dash orb softlocked.
    if 'TFormStartHost.Create(Self)' not in text:
        bad.append('GmMain is not passing a TFormStartHost - a bare TStartHost '
                   'returns False from Opening, so the cutscene never runs')
    # The SAME omission, twice: TStartHost has two do-nothing virtuals and both
    # were left unoverridden. Opening meant no cutscene; PlayMusic meant stage 1
    # ran in silence, because GameStartOrLoad starts the stage music through it.
    if 'procedure TFormStartHost.PlayMusic' not in text:
        bad.append('TFormStartHost does not override PlayMusic - '
                   'GameStartOrLoad starts the stage music through it and the '
                   'base class does nothing, so the stage plays in silence')
    # THE THIRD TIME. TSessionAudio's two methods are no-op defaults too, and
    # nothing overrode them, so event sub-op 9 (sound) and sub-op 12 (music)
    # both ran silently. The pattern is now the thing being guarded, not the
    # individual bugs: a base class whose defaults do nothing is invisible
    # until someone plays the game.
    if 'TFormAudio = class(TSessionAudio)' not in text:
        bad.append("there is no TFormAudio - the TSessionAudio defaults do "
                   'nothing, so event sounds and event music are silent')
    if 'FSession.Audio := TFormAudio.Create' not in text:
        bad.append('TFormAudio exists but is not installed on the session')

    # The frame CLOCK. GetTickCount64 steps 15-16 ms on Windows, so reading it
    # here held the game to 40 fps against the original's 62. The original
    # reads timeGetTime, which is also the only one of the two that exists on
    # an XP target.
    # Comments mention the wrong clock on purpose, to say why it is wrong, so
    # strip them before looking - the first version of this check failed on its
    # own explanatory comment.
    idle_code = re.sub(r'[{][^}]*[}]', ' ', idle)
    if 'GetTickCount64' in idle_code:
        bad.append('AppIdle reads GetTickCount64 - it steps 15-16 ms on '
                   'Windows, which caps the frame rate near 40. The original '
                   'reads timeGetTime; use FrameClockMs')
    if 'FrameClockMs' not in idle_code:
        bad.append('AppIdle does not read FrameClockMs')
    if 'BeginFrameClock' not in text:
        bad.append('nothing calls BeginFrameClock - without timeBeginPeriod(1) '
                   'the Sleep(1) in AppIdle takes about 15.6 ms and caps the '
                   'frame rate anyway')
    for cb in ('FDialogue.OnSound', 'FDialogue.OnMusic',
               'FDialogue.OnStopMusic'):
        if cb not in text:
            bad.append('%s is not wired - without the fanfare the power-up '
                       'panel has nothing to dismiss it' % cb)

    dlg = open(os.path.join(REPO, 'src', 'Dialogue.pas'), encoding='utf-8').read()
    seg = dlg[dlg.index('procedure TDialogueBox.SubMode'):]
    seg = seg[:seg.index(chr(10) + 'end;')]
    # Each is guarded by Assigned(X) and then CALLED, so the bare name appears
    # twice. Testing for the name alone is not enough: deleting the call leaves
    # the Assigned() guard behind and the check still passed - which it did,
    # under mutation, before this was tightened.
    for name, call in (('FOnSound', r'FOnSound\s*\('),
                       ('FOnStopMusic', r'^\s*FOnStopMusic\s*;'),
                       ('FOnMusic', r'FOnMusic\s*\(')):
        if not re.search(r'Assigned\s*\(\s*%s\s*\)' % name, seg) or            not re.search(call, seg, re.M):
            bad.append('TDialogueBox.SubMode does not guard AND call %s - '
                       'PowerUp_Show plays effect $10, STOPS the music, then '
                       'starts playlist entry 4, and the panel is dismissed by '
                       'that track ending' % name)

    if bad:
        print('FAIL - the frame loop no longer matches the traced game:')
        for b in bad:
            print('  %s' % b)
        return 1

    print('frame loop OK - %d pre arms, %d post arms, entity update '
          'unconditional between them; opening and power-up audio wired'
          % (len(got_pre), len(got_post)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
