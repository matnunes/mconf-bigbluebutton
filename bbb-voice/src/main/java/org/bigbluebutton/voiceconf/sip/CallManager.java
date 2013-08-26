/**
* BigBlueButton open source conferencing system - http://www.bigbluebutton.org/
* 
* Copyright (c) 2012 BigBlueButton Inc. and by respective authors (see below).
*
* This program is free software; you can redistribute it and/or modify it under the
* terms of the GNU Lesser General Public License as published by the Free Software
* Foundation; either version 3.0 of the License, or (at your option) any later
* version.
* 
* BigBlueButton is distributed in the hope that it will be useful, but WITHOUT ANY
* WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
* PARTICULAR PURPOSE. See the GNU Lesser General Public License for more details.
*
* You should have received a copy of the GNU Lesser General Public License along
* with BigBlueButton; if not, see <http://www.gnu.org/licenses/>.
*
*/
package org.bigbluebutton.voiceconf.sip;

import java.util.Collection;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

public class CallManager {

	private final Map<String, CallAgent> calls = new ConcurrentHashMap<String, CallAgent>();
	private final Map<String, CallAgent> callsGlobal = new ConcurrentHashMap<String, CallAgent>();
	
	public CallAgent add(CallAgent ca) {
		return calls.put(ca.getCallId(), ca);
	}

	public CallAgent addGlobal(CallAgent ca) {
		return callsGlobal.put(ca.getCallId(), ca);	
	}

	public CallAgent remove(String id) {
		return calls.remove(id);
	}
	
	public CallAgent removeGlobal(String id) {
		return callsGlobal.remove(id);
	}
	
	
	public CallAgent get(String id) {
		return calls.get(id);
	}
	
	public CallAgent getGlobal(String id) {
		return callsGlobal.get(id);
	}

	public Collection<CallAgent> getAll() {
		return calls.values();
	}

	public Collection<CallAgent> getAllGlobal() {
		return callsGlobal.values();
	}


}
