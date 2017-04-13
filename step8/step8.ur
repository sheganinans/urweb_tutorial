datatype mod = Incr | Decr

datatype diff
  = New of int * int
  | Del of int
  | Mod of int * mod
		      
type counter = { Id : int, Count : int }

sequence counter_seq
table counters : { Id : int, Count : int }
		     PRIMARY KEY Id

sequence user_seq
table users : { Client : client, Chan : channel diff }
		  PRIMARY KEY Client
		 
fun render (diff : diff) (sl : source (list counter)) =
    case diff of
	New (i, c) =>
	l <- get sl;
	set sl ({Id = i, Count = c} :: l)
      | Del i =>
	l <- get sl;
	set sl (List.filter (fn x => x.Id <> i) l)
      | Mod (i, m) =>
	l <- get sl;
	set sl (List.mp (fn x =>
			     if eq x.Id i
			     then case m of
				      Incr => x -- #Count ++ {Count = x.Count + 1}
				    | Decr => x -- #Count ++ {Count = x.Count - 1}
			     else x) l)

fun newCounter () =
    n <- nextval counter_seq;
    dml (INSERT INTO counters (Id, Count) VALUES ({[n]}, 0));
    usrs <- queryL (SELECT * FROM users);
    _ <- List.mapM (fn x => send x.Users.Chan (New (n, 0))) usrs;
    return ()
    
fun onLoad () =
    me <- self;
    user <- oneRow (SELECT *
		    FROM users
		    WHERE users.Client = {[me]});
    ctrs <- queryL (SELECT * FROM counters);
    
    _ <- List.mapM (fn x => send user.Users.Chan (New (x.Counters.Id,
						       x.Counters.Count))) ctrs;
    return ()

fun mod (diff : diff) =
    case diff of
	Mod (id, m) => (
	r <- oneOrNoRows (SELECT *
			  FROM counters
			  WHERE counters.Id = {[id]});
	case r of
	    Some c => (case m of
			  Incr =>
			  dml (UPDATE counters
			       SET Count = Count + 1
			       WHERE Id = {[c.Counters.Id]})
			| Decr =>
			  dml (UPDATE counters
			       SET Count = Count - 1
			       WHERE Id = {[c.Counters.Id]}));
	    usrs <- queryL (SELECT * FROM users);
	    _ <- List.mapM (fn x => send x.Users.Chan diff) usrs;
	    return ()
	  | None => return ())
      | Del id =>
	dml (DELETE FROM counters WHERE Id = {[id]});
	usrs <- queryL (SELECT * FROM users);
	_ <- List.mapM (fn x => send x.Users.Chan diff) usrs;
	return ()
      | _ => return ()
    
fun counters () =
    me <- self;
    chan <- channel;
    dml (INSERT INTO users (Client, Chan) VALUES ({[me]}, {[chan]}));
    
    sl <- source ([] : list counter);

    return <xml><body onload={let fun loop () =
				      x <- recv chan;
				      render x sl;
				      sleep 1;
				      loop ()
			      in rpc (onLoad ());
				 loop ()
			      end }>
      
      <button value="Add" onclick={fn _ => x <- rpc (newCounter ()); return ()}/><br/>

      <dyn signal={l <- signal sl;
		   return (List.mapX
			       (fn {Id = i, Count = c} => <xml>
				 {[c]}
				 <button value="Incr"
				 onclick={fn _ =>
					     x <- rpc (mod (Mod (i, Incr)));
					     return ()}/>
				 <button value="Decr"
				 onclick={fn _ =>
					     x <- rpc (mod (Mod (i, Decr)));
					     return ()}/>
				 <button value="Del"
				 onclick={fn _ =>
					     x <- rpc (mod (Del i));
					     return ()}/><br/></xml>)
			       (List.sort (fn a b => gt a.Id b.Id) l)) }/>
	
    </body></xml>
    
fun main () = return <xml><body>
  <form><submit value="login" action={counters}/></form>
</body></xml>