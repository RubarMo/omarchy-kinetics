// Small, dependency-free helpers shared by the visual plugin and its tests.

function wholeNumber(value, fallback, minimum, maximum) {
  var number = Math.floor(Number(value))
  if (!isFinite(number)) number = fallback
  return Math.max(minimum, Math.min(maximum, number))
}

function minutes(value, fallback) {
  return wholeNumber(value, fallback, 1, 120)
}

function rounds(value, fallback) {
  return wholeNumber(value, fallback, 1, 12)
}

function plan(sitting, standing, moving, roundCount) {
  return {
    sittingMinutes: minutes(sitting, 20),
    standingMinutes: minutes(standing, 8),
    movingMinutes: minutes(moving, 2),
    rounds: rounds(roundCount, 3)
  }
}

function phaseDurationSeconds(sessionPlan, phase) {
  var value = sessionPlan || plan(20, 8, 2, 3)
  if (phase === "standing") return minutes(value.standingMinutes, 8) * 60
  if (phase === "moving") return minutes(value.movingMinutes, 2) * 60
  return minutes(value.sittingMinutes, 20) * 60
}

function totalSeconds(sessionPlan) {
  var value = sessionPlan || plan(20, 8, 2, 3)
  return (minutes(value.sittingMinutes, 20)
    + minutes(value.standingMinutes, 8)
    + minutes(value.movingMinutes, 2)) * rounds(value.rounds, 3) * 60
}

function phaseLabel(phase) {
  if (phase === "standing") return "Standing"
  if (phase === "moving") return "Moving"
  return "Sitting"
}

function nextPhase(phase) {
  if (phase === "sitting") return "standing"
  if (phase === "standing") return "moving"
  return "sitting"
}

function emptyTotals() {
  return { sitting: 0, standing: 0, moving: 0 }
}

function totalsFrom(value) {
  var source = value || {}
  return {
    sitting: Math.max(0, Number(source.sitting) || 0),
    standing: Math.max(0, Number(source.standing) || 0),
    moving: Math.max(0, Number(source.moving) || 0)
  }
}
