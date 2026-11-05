export function states() {
  const self = { id: 'a', name: 'Nyx', skin: 0, hunter: false, x: .3, y: .4,
    health: '9999999999999999999999999', maxHealth: '9999999999999999999999999', shotAge: 4, combatTargetId: null };
  const enemy = { id: 'b', name: 'Noctis', skin: 3, hunter: false, x: .6, y: .5, health: 100, maxHealth: 100, lookX: 1, lookY: 0 };
  const base={ type: 'state', id: 'a', round: 1, map: 'courtyard', mode:'pvp',pvp:true,
    pvpRulesVersion:1, running:true, elapsed: 0, walls:[[.1,.2,.3,.4]], projectiles: [], optional:null, self, players:[enemy] };
  const second={...base,elapsed:.05,self:{...self,x:.30001},players:[{...enemy,x:.59999,combatTargetId:'a'}]};
  delete second.players[0].lookX;delete second.players[0].lookY;delete second.optional;
  const hidden={...second,elapsed:.1,players:[]};
  const returned={...hidden,elapsed:.15,players:[{...enemy,x:.7,health:99}]};
  const rematch={...base,round:2,elapsed:0,self:{...self,x:.2},players:[{...enemy,powerLeft:3}]};
  const nextMap={...rematch,map:'volcano',walls:[[.2,.3,.1,.1]],elapsed:.05};
  return [base,second,hidden,returned,rematch,nextMap];
}
// Test-only independent implementation of the on-wire contract.
export function expand(frames) {
  let root={},actors=new Map(),keys=[];
  return frames.map(frame=>{
    if(frame.base===0){root={};actors=new Map();}
    if(frame.keys)keys=frame.keys;
    root={...root,...frame.set};for(const key of frame.unset)delete root[key];
    for(const [id,pairs,unset] of frame.actors){
      const actor={...actors.get(id)};
      for(let i=0;i<pairs.length;i+=2)actor[keys[pairs[i]]]=pairs[i+1];
      for(const index of unset)delete actor[keys[index]];
      actors.set(id,actor);
    }
    for(const id of actors.keys())if(!frame.visible.includes(id))actors.delete(id);
    return {...root,self:actors.get(root.id),players:frame.visible.filter(id=>id!==root.id).map(id=>actors.get(id))};
  });
}
