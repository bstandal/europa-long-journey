import { ArrowDown, ArrowLeft, ArrowUp } from "@phosphor-icons/react";

const chapterClaim =
  "Western Rome fell, but its Christian inheritance did not. Bishops, monasteries and kings rebuilt it as a commonwealth that could survive without one empire.";

export function App() {
  const enterChapter = () => {
    document.querySelector("#chapter-preview")?.scrollIntoView({
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
        <a className="road-link" href="#chapter-preview">
          <ArrowLeft aria-hidden="true" weight="regular" />
          <span>The long road</span>
        </a>
      </header>

      <section className="chapter-opening" id="opening" aria-labelledby="chapter-title">
        <div className="opening-copy">
          <div className="copy-inner">
            <div className="chapter-meta">
              <span>07</span>
              <span aria-hidden="true">·</span>
              <span>AD 500–1000</span>
            </div>

            <h1 id="chapter-title">
              <span>Europe</span>
              <span>Reborn</span>
            </h1>

            <p className="chapter-claim">{chapterClaim}</p>

            <button className="opening-action" type="button" onClick={enterChapter}>
              <span>Follow the rebuilt road</span>
              <ArrowDown aria-hidden="true" weight="regular" />
            </button>
          </div>
        </div>

        <figure className="opening-visual" aria-label="A Carolingian scriptorium opening onto a winter road">
          <img
            src="/assets/chapter-07-written-commonwealth.png"
            alt="A scribe works over vellum beside codices, wax tablets and a reused Roman column while a royal messenger rides away through a round stone arch."
          />
        </figure>

        <div className="continuity-rule" aria-hidden="true"></div>
      </section>

      <section className="chapter-preview" id="chapter-preview" aria-labelledby="preview-title">
        <div className="preview-copy">
          <p className="preview-eyebrow">A commonwealth without one empire</p>
          <h2 id="preview-title">The word travels further than the king.</h2>
          <p>
            A ruler moves from hall to hall. The order travels through bishops, counts,
            monasteries and written law. Roman stone remains underfoot while a new political
            world learns to connect itself.
          </p>
          <button
            className="return-action"
            type="button"
            onClick={() =>
              document.querySelector("#opening")?.scrollIntoView({
                behavior: "smooth",
                block: "start",
              })
            }
          >
            <ArrowUp aria-hidden="true" weight="regular" />
            <span>Return to the opening</span>
          </button>
        </div>
      </section>
    </main>
  );
}
