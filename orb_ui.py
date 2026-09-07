"""
orb_ui.py — the visual companion window: a glowing, pulsing orb that reflects
the assistant's current state (idle / listening / thinking / speaking) and
reacts to live audio level. Pure pygame, no extra dependencies.

Runs on the main thread — it owns the window/render loop. The actual voice
assistant logic runs in a background thread and just updates a shared
AssistantState object; this file only ever reads from it.

Closing the orb window shuts down the whole assistant (simplest v1 behavior).
"""

import math
import time
import os
import pygame

WINDOW_SIZE = 480
FPS = 60
BASE_RADIUS = 70

COLORS = {
    "idle":      (70, 130, 200),   # calm blue
    "listening": (60, 200, 140),   # green
    "thinking":  (170, 90, 220),   # violet
    "speaking":  (250, 170, 60),   # warm gold
}


def _draw_orb(surface, center, level, color, t):
    # gentle breathing motion, layered on top of live/animated audio level
    breathe = (math.sin(t * 1.6) + 1) / 2  # 0..1
    pulse = BASE_RADIUS * (1.0 + 0.15 * breathe + 0.35 * level)

    # aura: soft, layered, low-alpha rings behind the core orb
    for i in range(4, 0, -1):
        ring_radius = int(pulse + i * 14 + level * 20)
        if ring_radius <= 0:
            continue
        alpha = max(0, 60 - i * 12 - int(level * 10))
        ring_surf = pygame.Surface((ring_radius * 2, ring_radius * 2), pygame.SRCALPHA)
        pygame.draw.circle(ring_surf, (*color, alpha), (ring_radius, ring_radius), ring_radius)
        surface.blit(
            ring_surf,
            (center[0] - ring_radius, center[1] - ring_radius),
            special_flags=pygame.BLEND_RGBA_ADD,
        )

    # core orb
    core_radius = max(1, int(pulse))
    core_surf = pygame.Surface((core_radius * 2, core_radius * 2), pygame.SRCALPHA)
    pygame.draw.circle(core_surf, (*color, 230), (core_radius, core_radius), core_radius)
    surface.blit(core_surf, (center[0] - core_radius, center[1] - core_radius))

    # bright inner highlight for a bit of depth
    highlight_radius = max(4, int(core_radius * 0.35))
    pygame.draw.circle(
        surface,
        (255, 255, 255),
        (center[0] - core_radius // 4, center[1] - core_radius // 4),
        highlight_radius,
    )


def run_orb(state):
    pygame.init()
    pygame.display.set_caption("Jairus")
    screen = pygame.display.set_mode((WINDOW_SIZE, WINDOW_SIZE))
    clock = pygame.time.Clock()
    center = (WINDOW_SIZE // 2, WINDOW_SIZE // 2)

    start_time = time.time()
    running = True

    while running:
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                running = False

        status, level = state.get_snapshot()
        color = COLORS.get(status, COLORS["idle"])
        t = time.time() - start_time

        screen.fill((12, 12, 20))  # near-black background so the glow pops
        _draw_orb(screen, center, level, color, t)
        pygame.display.flip()
        clock.tick(FPS)

    pygame.quit()
    os._exit(0)  # background assistant thread is a daemon, so this cleanly ends everything
