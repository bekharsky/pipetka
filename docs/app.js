const year = document.querySelector("#year");
if (year) year.textContent = new Date().getFullYear();

const revealItems = [...document.querySelectorAll(".reveal")];
if ("IntersectionObserver" in window) {
  const observer = new IntersectionObserver(
    (entries, currentObserver) => {
      for (const entry of entries) {
        if (!entry.isIntersecting) continue;
        entry.target.classList.add("is-visible");
        currentObserver.unobserve(entry.target);
      }
    },
    { threshold: 0.12, rootMargin: "0px 0px -30px 0px" },
  );
  revealItems.forEach((element) => observer.observe(element));
} else {
  revealItems.forEach((element) => element.classList.add("is-visible"));
}
