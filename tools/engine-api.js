
// ---- API used by the iPhone app (JavaScriptCore). Everything goes in and out as JSON strings. ----
var IMC = {
  version: VERSION,
  topics: function(){
    return JSON.stringify(Object.keys(TOPICS).map(function(id){
      var t = TOPICS[id];
      return {id: id, name: t.name, group: t.group, status: t.status, note: t.note};
    }));
  },
  plan: function(seed, statsJSON, size, only, unlockedJSON){
    var qs = planSession(seed, JSON.parse(statsJSON || '{}'), size, only || null, JSON.parse(unlockedJSON || '[]'));
    return JSON.stringify(qs.map(function(q){
      return {topic: q.topic, variant: q.variant, seed: q.seed, prompt: q.prompt, options: q.options,
              correct: q.correct, hint: q.hint, explain: q.explain, stretch: !!q.stretch,
              diagram: q.diagram || null};
    }));
  },
  checkPassword: function(word){ return checkPassword(word) || ''; },
  code: function(metaJSON, resultsJSON){ return buildSessionCode(JSON.parse(metaJSON), JSON.parse(resultsJSON)); }
};
