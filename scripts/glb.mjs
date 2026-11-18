// Collect by material for predictable draw calls on WebGL 2. Coordinates are Y-up, metres.
import fs from 'node:fs';

export function makeGlb() {
  const gltf = { asset: {version:'2.0',generator:'Cooper Woodland | CC0 scene'},
    scene:0, scenes:[{nodes:[]}], nodes:[], meshes:[], materials:[], images:[],
    textures:[], samplers:[{magFilter:9729,minFilter:9987,wrapS:10497,wrapT:10497}],
    buffers:[{byteLength:0}], bufferViews:[], accessors:[] };
  const chunks=[], batches=new Map();
  let nbytes=0;
  function view(data,target) {
    const id=gltf.bufferViews.length;
    gltf.bufferViews.push({buffer:0,byteOffset:nbytes,byteLength:data.byteLength,...(target?{target}:{})});
    const pad=(4-data.byteLength%4)%4;
    chunks.push(data,Buffer.alloc(pad)); nbytes+=data.byteLength+pad;return id;
  }
  function texture(name) {
    const bytes=fs.readFileSync('shared/textures/'+name);
    const i=gltf.images.push({name,bufferView:view(bytes),mimeType:name.endsWith('.jpg')?'image/jpeg':'image/png'})-1;
    return {index:gltf.textures.push({sampler:0,source:i})-1};
  }
  function material(name,source,opts={}) {
    const pbr={baseColorFactor:opts.tint||[1,1,1,1],metallicFactor:0,roughnessFactor:opts.rough??1};
    const m={name,pbrMetallicRoughness:pbr,doubleSided:!!opts.twoSided};
    if(source){
      pbr.baseColorTexture=texture(source+'_diff.jpg');
      pbr.metallicRoughnessTexture=texture(source+'_arm.jpg');
      m.occlusionTexture={...pbr.metallicRoughnessTexture,strength:.74};
      m.normalTexture={...texture(source+'_nor_gl.jpg'),scale:opts.normal??.76};
    }
    if(opts.card){pbr.baseColorTexture=texture(opts.card+'.png');m.alphaMode='MASK';m.alphaCutoff=.35;}
    if(opts.imageUri){
      const sourceIndex=gltf.images.push({uri:opts.imageUri})-1;
      pbr.baseColorTexture={index:gltf.textures.push({sampler:0,source:sourceIndex})-1};
      if(opts.cutoff){m.alphaMode='MASK';m.alphaCutoff=opts.cutoff;}
    }
    if(opts.glow)m.emissiveFactor=opts.glow;
    const id=gltf.materials.push(m)-1;
    const batch={p:[],n:[],uv:[],c:[],ix:[],id,name};
    batches.set(name,batch);return batch;
  }
  function vert(batch,p,n,uv,c=[1,1,1]) {
    const i=batch.p.length/3;
    batch.p.push(...p);batch.n.push(...n);batch.uv.push(...uv);
    batch.c.push(...c.map(x=>Math.round(Math.min(1,Math.max(0,x))*255)),255);
    return i;
  }
  function write(file) {
    const acc=(arr,kind,type,width,target,normalized=false,bounds=false)=>{
      const C=kind===5126?Float32Array:kind===5125?Uint32Array:kind===5123?Uint16Array:Uint8Array;
      const accessor={bufferView:view(Buffer.from(new C(arr).buffer),target),componentType:kind,count:arr.length/width,type};
      if(normalized)accessor.normalized=true;
      if(bounds){
        accessor.min=new Array(width).fill(Infinity);accessor.max=new Array(width).fill(-Infinity);
        for(let i=0;i<arr.length;i++){let j=i%width;accessor.min[j]=Math.min(accessor.min[j],arr[i]);accessor.max[j]=Math.max(accessor.max[j],arr[i]);}
      }
      return gltf.accessors.push(accessor)-1;
    };
    let triangles=0;
    for(const b of batches.values()){
      if(!b.ix.length)continue;
      const attributes={POSITION:acc(b.p,5126,'VEC3',3,34962,false,true),NORMAL:acc(b.n,5126,'VEC3',3,34962),TEXCOORD_0:acc(b.uv,5126,'VEC2',2,34962),COLOR_0:acc(b.c,5121,'VEC4',4,34962,true)};
      const indices=acc(b.ix,b.p.length/3<=65535?5123:5125,'SCALAR',1,34963);
      const mesh=gltf.meshes.push({name:b.name,primitives:[{attributes,indices,material:b.id}]})-1;
      gltf.scenes[0].nodes.push(gltf.nodes.push({name:b.name,mesh})-1);triangles+=b.ix.length/3;
    }
    gltf.buffers[0].byteLength=nbytes;
    const js=Buffer.from(JSON.stringify(gltf));const json=Buffer.concat([js,Buffer.alloc((4-js.length%4)%4,32)]);
    const bytes=Buffer.concat(chunks), header=Buffer.alloc(20), bin=Buffer.alloc(8);
    header.write('glTF');header.writeUInt32LE(2,4);header.writeUInt32LE(28+json.length+bytes.length,8);header.writeUInt32LE(json.length,12);header.write('JSON',16);
    bin.writeUInt32LE(bytes.length);bin.write('BIN\0',4);
    fs.writeFileSync(file,Buffer.concat([header,json,bin,bytes]));return triangles;
  }
  return {material,vert,write};
}
