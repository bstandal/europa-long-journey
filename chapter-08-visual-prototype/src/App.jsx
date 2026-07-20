import { ArrowLeft, ArrowUp } from "@phosphor-icons/react";

const chapterClaim =
  "Pope, emperor, bishops and princes learned to rule through rival courts that neither side could absorb.";

export function App() {
  const returnToOpening = () => {
    document.querySelector("#opening")?.scrollIntoView({
      behavior: "smooth",
      block: "start",
    });
  };

  return (
    <main className="chapter-shell">
      <header className="site-header" aria-label="Primary navigation">
        <a className="wordmark" href="#opening" aria-label="EUROPA, return to chapter opening">
          EUROPA
        </a>
        <a
          className="road-link"
          href="https://bstandal.github.io/europa-long-journey/#papal-revolution"
          aria-label="Return to the long road"
        >
          <ArrowLeft aria-hidden="true" weight="regular" />
          <span>The long road</span>
        </a>
      </header>

      <section className="chapter-opening" id="opening" aria-labelledby="chapter-title">
        <figure
          className="opening-visual"
          aria-label="A papal reform synod and a royal-princely court work in separate Romanesque chambers while a messenger carries a document between them."
        >
          <img
            src="/assets/two-courts-hero.png"
            alt="Clerics and bishops debate around a sealed register on the left while princes, bishops and a royal chancellor examine a charter on the right; a messenger crosses the central doorway."
          />
        </figure>

        <div className="opening-copy">
          <p className="chapter-meta">08 · AD 1046–1123</p>
          <h1 id="chapter-title">
            <span>The</span>
            <span>Papal</span>
            <span>Revolution</span>
          </h1>
          <p className="chapter-claim">{chapterClaim}</p>
          <a className="opening-action" href="#chapter-preview">
            Enter the contested order
          </a>
        </div>
      </section>

      <section className="chapter-preview" id="chapter-preview" aria-labelledby="preview-title">
        <div className="preview-copy">
          <p className="preview-eyebrow">Act I · Reform moves to Rome · AD 1046</p>
          <h2 id="preview-title">The Emperor Judges Three Popes</h2>
          <p>
            Henry III crossed the Alps to receive the imperial crown and entered a Roman church
            divided by three rival claimants. At Sutri, a royal protector could still convene
            bishops, judge the crisis and help install a reforming pope.
          </p>
          <p>
            The intervention joined two forces that would soon pull apart. Reformers needed royal
            power to end Roman faction, while the king treated protection of the Church as part of
            sacred government. Within a generation, the procedures built in Rome would be used to
            resist the hand that had restored them.
          </p>
          <button className="return-action" type="button" onClick={returnToOpening}>
            <ArrowUp aria-hidden="true" weight="regular" />
            <span>Return to the two courts</span>
          </button>
        </div>

        <aside className="preview-instrument" aria-label="The chapter's institutional mechanism">
          <span className="instrument-label">One Christian order</span>
          <strong>Two organised jurisdictions</strong>
          <p>Synod · register · election</p>
          <p>Assembly · charter · regalia</p>
        </aside>
      </section>
    </main>
  );
}
