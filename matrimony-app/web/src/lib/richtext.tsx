import { Fragment } from "react";

/** Tiny formatter for assistant answers: **bold** and line breaks. No HTML injection. */
export function RichText({ text }: { text: string }) {
  return (
    <>
      {text.split("\n").map((line, i) => (
        <Fragment key={i}>
          {i > 0 && <br />}
          {line.split(/(\*\*[^*]+\*\*)/g).map((part, j) =>
            part.startsWith("**") && part.endsWith("**") ? <strong key={j}>{part.slice(2, -2)}</strong> : <Fragment key={j}>{part}</Fragment>,
          )}
        </Fragment>
      ))}
    </>
  );
}
