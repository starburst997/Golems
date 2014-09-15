package net.rezmason.utils.workers;

import haxe.io.Bytes;

#if flash
    import flash.system.MessageChannel;
    import flash.system.Worker;
    import flash.system.WorkerDomain;
#elseif cpp
    import cpp.vm.Thread;
#elseif neko
    import neko.vm.Thread;
#end

#if macro
    import haxe.macro.Context;
    import haxe.macro.Expr;
#end

#if (flash || js)
    typedef Core<TInput, TOutput> = Bytes;
#elseif (neko || cpp)
    typedef Core<TInput, TOutput> = Class<BasicWorker<TInput, TOutput>>;
    typedef Worker = Thread;
#end

#if !macro @:autoBuild(net.rezmason.utils.workers.BasicBoss.build()) #end class BasicBoss<TInput, TOutput> {

    var worker:Worker;

    #if flash
        var incoming:MessageChannel;
        var outgoing:MessageChannel;
    #end

    private function __initAliases():Void {}

    public function new(core:Core<TInput, TOutput>):Void {
        __initAliases();
        #if flash
            worker = WorkerDomain.current.createWorker(core.getData());
            incoming = worker.createMessageChannel(Worker.current);
            outgoing = Worker.current.createMessageChannel(worker);
            worker.setSharedProperty('incoming', outgoing);
            worker.setSharedProperty('outgoing', incoming);
            incoming.addEventListener('channelMessage', onIncoming);
        #elseif js
            var blob = new Blob([core.toString()]);
            var url:String = untyped __js__('window').URL.createObjectURL(blob);
            worker = new Worker(url);
            worker.addEventListener('message', onIncoming);
        #elseif (neko || cpp)
            worker = encloseInstance(core, onIncoming);
        #end
    }

    public function start():Void {
        #if flash
            worker.start();
        #end
    }

    public function die():Void {
        #if (flash || js)
            worker.terminate();
        #elseif (neko || cpp)
            worker.sendMessage('__die__');
        #end
    }

    public function send(data:TInput):Void {
        #if flash
            outgoing.send(data);
        #elseif js
            worker.postMessage(data);
        #elseif (neko || cpp)
            worker.sendMessage(data);
        #end
    }

    function receive(data:TOutput):Void {}

    function onIncoming(data:Dynamic):Void {
        #if flash
            data = incoming.receive();
        #elseif js
            data = data.data;
        #end

        if (Reflect.hasField(data, '__error')) onErrorIncoming(data.__error);
        else receive(data);
    }

    function onErrorIncoming(error:Dynamic):Void throw error;

    #if (neko || cpp)
        static function encloseInstance<TInput, TOutput>(clazz:Class<BasicWorker<TInput, TOutput>>, incoming:Dynamic->Void):Thread {
            function func():Void {
                var __clazz:Class<BasicWorker<TInput, TOutput>> = Thread.readMessage(true);
                var __outgoing:TOutput->Void = Thread.readMessage(true);
                var instance:BasicWorker<TInput, TOutput> = Type.createInstance(__clazz, []);
                instance.breathe(Thread.readMessage.bind(true), __outgoing);
            }

            var thread:Thread = Thread.create(func);
            thread.sendMessage(clazz);
            thread.sendMessage(incoming);

            return thread;
        }
    #end

    macro public static function build():Array<Field> {
        var fields:Array<Field> = Context.getBuildFields();

        fields = fields.filter(function(field) return field.name != '__initAliases');

        if (Context.defined('flash')) {
            // Crack open the input and output types, find classes inside and alias them
            var aliasExpressions:Array<Expr> = [];
            aliasExpressions.push(macro var registerAlias = untyped __global__["flash.net.registerClassAlias"]);

            for (type in Context.getLocalClass().get().superClass.params) {
                switch (type) {
                    case TInst(t, params):
                        var classType = t.get();
                        var isValidType:Bool = true;
                        switch (classType.kind) {
                            case KTypeParameter(constraints): isValidType = false;
                            case _:
                        }
                        if (isValidType) {
                            var qname:String = '${classType.pack.join('.')}.${classType.name}';
                            aliasExpressions.push(macro registerAlias($v{qname}, $i{classType.name}));
                        }
                    case _:
                }
            }

            var func:Function = {params:[], args:[], ret:null, expr:macro $b{aliasExpressions}};
            fields.push({ name:'__initAliases', access:[APrivate, AOverride], kind:FFun(func), pos:Context.currentPos() });
        }

        return fields;
    }
}

#if js
    @:native("Blob")
    extern class Blob {
       public function new(strings:Array<String> ) : Void;
    }

    @:native("Worker")
    extern class Worker {
        public function new(script:String):Void;
        public function postMessage(msg:Dynamic):Void;
        public function addEventListener(type:Dynamic, cb:Dynamic->Void):Void;
        public function terminate():Void;
    }
#end
