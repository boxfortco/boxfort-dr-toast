/**
 * Below-the-fold marketing on the join screen (repurposed from iOS OnboardingView).
 * Shown only when the player has not joined a room yet.
 */
export function LandingMarketing() {
  return (
    <div className="flex flex-col gap-10 pb-4 pt-2">
      <section className="rounded-2xl border-2 border-dashed border-stone-300 bg-[#faf7f2] p-6 shadow-[4px_4px_0_0_rgba(120,113,108,0.2)]">
        <h2 className="font-serif text-xl font-bold text-stone-900">
          The chase is on
        </h2>
        <p className="mt-2 text-pretty text-sm leading-relaxed text-stone-700">
          Detective Toast is hot on the trail of the elusive{" "}
          <strong className="font-semibold text-stone-900">Burnt Toast</strong> —
          slippery, smoky, and nowhere near the real answer.
        </p>
      </section>

      <section className="rounded-2xl border-2 border-dashed border-stone-300 bg-[#faf7f2] p-6 shadow-[4px_4px_0_0_rgba(120,113,108,0.2)]">
        <div className="flex flex-col gap-4 md:flex-row md:items-center">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src="/characters/chief_loaf.jpg"
            alt=""
            className="mx-auto h-40 w-40 shrink-0 rounded-2xl border-2 border-dashed border-stone-400/35 object-cover shadow-inner md:mx-0"
          />
          <div>
            <h2 className="font-serif text-xl font-bold text-stone-900">
              One host, a room full of phones
            </h2>
            <p className="mt-2 text-pretty text-sm leading-relaxed text-stone-700">
              Someone runs the game on the big screen. Everyone else opens this
              page on their own phone, enters the room code, and plays their slice.
              No sign-ups — just crumbs and chaos.
            </p>
          </div>
        </div>
      </section>

      <section className="rounded-2xl border-2 border-dashed border-stone-300 bg-white/90 p-6 shadow-[4px_4px_0_0_rgba(120,113,108,0.2)]">
        <h2 className="text-center font-serif text-xl font-bold text-stone-900">
          Which slice are you?
        </h2>
        <p className="mx-auto mt-2 max-w-prose text-pretty text-center text-sm leading-relaxed text-stone-700">
          <strong>Detective Toasts</strong> share the secret word and picture.{" "}
          <strong>Burnt Toast</strong> gets neither — only nerves of stale bread.
        </p>
        <div className="mt-5 grid grid-cols-2 gap-3">
          <figure className="rounded-xl border-2 border-blue-800/15 bg-blue-50/80 p-3 text-center shadow-sm">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img
              src="/characters/detective_toast.jpg"
              alt=""
              className="mx-auto h-28 w-full rounded-xl object-cover"
            />
            <figcaption className="mt-2 text-xs font-semibold text-stone-800">
              Detective Toast
            </figcaption>
          </figure>
          <figure className="rounded-xl border-2 border-orange-600/25 bg-orange-50/90 p-3 text-center shadow-sm">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img
              src="/characters/burnt_toast.jpg"
              alt=""
              className="mx-auto h-28 w-full rounded-xl object-cover"
            />
            <figcaption className="mt-2 text-xs font-semibold text-stone-800">
              Burnt Toast
            </figcaption>
          </figure>
        </div>
      </section>

      <section className="rounded-2xl border-2 border-dashed border-emerald-700/30 bg-emerald-50/70 p-6 shadow-[4px_4px_0_0_rgba(52,120,81,0.15)]">
        <div className="overflow-hidden rounded-xl border border-emerald-800/15 shadow-md">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src="/characters/detectives_won.jpg"
            alt=""
            className="h-auto w-full object-cover"
          />
        </div>
        <h2 className="mt-4 font-serif text-xl font-bold text-stone-900">
          One clue at a time
        </h2>
        <p className="mt-2 text-pretty text-sm leading-relaxed text-stone-700">
          Take turns dropping a word or phrase that fits the secret. Burnt Toast is
          flying blind — bluff, stall, or pray nobody notices.
        </p>
      </section>

      <section className="rounded-2xl border-2 border-dashed border-violet-600/35 bg-violet-50/80 p-6 shadow-[4px_4px_0_0_rgba(90,50,120,0.12)]">
        <div className="overflow-hidden rounded-xl border border-violet-800/15 shadow-md">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src="/characters/detective_toast_panic.jpg"
            alt=""
            className="h-auto w-full object-cover"
          />
        </div>
        <h2 className="mt-4 font-serif text-xl font-bold text-stone-900">
          Truth… or toaster smoke?
        </h2>
        <p className="mt-2 text-pretty text-sm leading-relaxed text-stone-700">
          Watch, listen, then vote when the table is ready. If Burnt Toast is
          caught, there is still a last chance — the final guess.
        </p>
      </section>

      <p className="text-center text-sm italic text-stone-600">
        Grab your crew, dim the lights, and don&apos;t trust the crust.
      </p>
    </div>
  );
}
