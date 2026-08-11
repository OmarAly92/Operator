export function OperatorLogo() {
  return (
    <span
      aria-label="Operator"
      className="inline-flex items-center gap-2 font-sans text-base font-medium leading-none tracking-[-0.5px] text-foreground"
    >
      <img
        src="/opr-logo.svg"
        alt=""
        width={20}
        height={20}
        aria-hidden="true"
        className="size-5 shrink-0"
      />
      <span>Operator</span>
    </span>
  );
}
