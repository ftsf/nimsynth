## #
## #  Copyright (C) 2001 Paul Davis
## #  Copyright (C) 2004 Jack O'Quin
## #
## #  This program is free software; you can redistribute it and/or modify
## #  it under the terms of the GNU Lesser General Public License as published by
## #  the Free Software Foundation; either version 2.1 of the License, or
## #  (at your option) any later version.
## #
## #  This program is distributed in the hope that it will be useful,
## #  but WITHOUT ANY WARRANTY; without even the implied warranty of
## #  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
## #  GNU Lesser General Public License for more details.
## #
## #  You should have received a copy of the GNU Lesser General Public License
## #  along with this program; if not, write to the Free Software
## #  Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
## #
## #

type
  jack_uuid* = uint64
  jack_shmsize* = int32

## #*
## #  Type used to represent sample frame counts.
## # 

type jack_native_thread* = pointer

type
  jack_nframes* = uint32

## #*
## #  Maximum value that can be stored in jack_nframes
## # 

const
  JACK_MAX_FRAMES* = (4294967295'i64) ## # This should be UINT32_MAX, but C++ has a problem with that. 

## #*
## #  Type used to represent the value of free running
## #  monotonic clock with units of microseconds.
## # 

type
  jack_time* = uint64

## #*
## #   Maximum size of @a load_init string passed to an internal client
## #   jack_initialize() function via jack_internal_client_load().
## # 

const
  JACK_LOAD_INIT_LIMIT* = 1024

## #*
## #   jack_intclient is an opaque type representing a loaded internal
## #   client.  You may only access it using the API provided in @ref
## #   intclient.h "<jack/intclient.h>".
## # 

type
  jack_intclient* = uint64

## #*
## #   jack_port is an opaque type.  You may only access it using the
## #   API provided.
## # 

type
  JackPort* = pointer

## #*
## #   JackClient is an opaque type.  You may only access it using the
## #   API provided.
## # 

type
  JackClient* = pointer

## #*
## #   Ports have unique ids. A port registration callback is the only
## #   place you ever need to know their value.
## # 

type
  JackPortId* = uint32
  JackPortTypeId* = uint32

## #*
## #   @ref jack_options bits
## # 

type
  JackOptions* = enum ## #*
                   ## #      Null value to use when no option bits are needed.
                   ## #     
    JackNullOption = 0x00000000, ## #*
                              ## #      Do not automatically start the JACK server when it is not
                              ## #      already running.  This option is always selected if
                              ## #      \$JACK_NO_START_SERVER is defined in the calling process
                              ## #      environment.
                              ## #     
    JackNoStartServer = 0x00000001, ## #*
                                 ## #      Use the exact client name requested.  Otherwise, JACK
                                 ## #      automatically generates a unique one, if needed.
                                 ## #     
    JackUseExactName = 0x00000002, ## #*
                                ## #      Open with optional <em>(char *) server_name</em> parameter.
                                ## #     
    JackServerName = 0x00000004, ## #*
                              ## #      Load internal client from optional <em>(char *)
                              ## #      load_name</em>.  Otherwise use the @a client_name.
                              ## #     
    JackLoadName = 0x00000008, ## #*
                            ## #      Pass optional <em>(char *) load_init</em> string to the
                            ## #      jack_initialize() entry point of an internal client.
                            ## #     
    JackLoadInit = 0x00000010, ## #*
                            ## #       pass a SessionID Token this allows the sessionmanager to identify the client again.
                            ## #      
    JackSessionID = 0x00000020


## #* Valid options for opening an external client. 

converter toInt*(x: JackOptions): int =
  result = x.int

const
  JackOpenOptions* = (JackSessionID or JackServerName or JackNoStartServer or JackUseExactName)

## #* Valid options for loading an internal client. 

const
  JackLoadOptions* = (JackLoadInit or JackLoadName or JackUseExactName)

## #*
## #   Options for several JACK operations, formed by OR-ing together the
## #   relevant @ref JackOptions bits.
## # 

type
  jack_options* = JackOptions


## #*
## #   @ref JackStatus bits
## # 

type
  JackStatus* = enum            ## #*
                  ## #      Overall operation failed.
                  ## #     
    JackFailure = 0x00000001, ## #*
                           ## #      The operation contained an invalid or unsupported option.
                           ## #     
    JackInvalidOption = 0x00000002, ## #*
                                 ## #      The desired client name was not unique.  With the @ref
                                 ## #      JackUseExactName option this situation is fatal.  Otherwise,
                                 ## #      the name was modified by appending a dash and a two-digit
                                 ## #      number in the range "-01" to "-99".  The
                                 ## #      jack_get_client_name() function will return the exact string
                                 ## #      that was used.  If the specified @a client_name plus these
                                 ## #      extra characters would be too long, the open fails instead.
                                 ## #     
    JackNameNotUnique = 0x00000004, ## #*
                                 ## #      The JACK server was started as a result of this operation.
                                 ## #      Otherwise, it was running already.  In either case the caller
                                 ## #      is now connected to jackd, so there is no race condition.
                                 ## #      When the server shuts down, the client will find out.
                                 ## #     
    JackServerStarted = 0x00000008, ## #*
                                 ## #      Unable to connect to the JACK server.
                                 ## #     
    JackServerFailed = 0x00000010, ## #*
                                ## #      Communication error with the JACK server.
                                ## #     
    JackServerError = 0x00000020, ## #*
                               ## #      Requested client does not exist.
                               ## #     
    JackNoSuchClient = 0x00000040, ## #*
                                ## #      Unable to load internal client
                                ## #     
    JackLoadFailure = 0x00000080, ## #*
                               ## #      Unable to initialize client
                               ## #     
    JackInitFailure = 0x00000100, ## #*
                               ## #      Unable to access shared memory
                               ## #     
    JackShmFailure = 0x00000200, ## #*
                              ## #      Client's protocol version does not match
                              ## #     
    JackVersionError = 0x00000400, ## #*
                                ## #      Backend error
                                ## #     
    JackBackendError = 0x00000800, ## #*
                                ## #      Client zombified failure
                                ## #     
    JackClientZombie = 0x00001000


converter toInt(x: JackStatus): int =
  return x.int


## #*
## #   Status word returned from several JACK operations, formed by
## #   OR-ing together the relevant @ref JackStatus bits.
## # 

## #*
## #   @ref jack_latency_callback_mode
## # 

type
  JackLatencyCallbackMode* = enum ## #*
                               ## #       Latency Callback for Capture Latency.
                               ## #       Input Ports have their latency value setup.
                               ## #       In the Callback the client needs to set the latency of the output ports
                               ## #      
    JackCaptureLatency, ## #*
                       ## #       Latency Callback for Playback Latency.
                       ## #       Output Ports have their latency value setup.
                       ## #       In the Callback the client needs to set the latency of the input ports
                       ## #      
    JackPlaybackLatency


## #*
## #   Type of Latency Callback (Capture or Playback)
## # 

type
  jack_latency_callback_mode* = JackLatencyCallbackMode


## #*
## #  Prototype for the client supplied function that is called
## #  by the engine when port latencies need to be recalculated
## # 
## #  @param mode playback or capture latency
## #  @param arg pointer to a client supplied data
## # 
## #  @return zero on success, non-zero on error
## # 

type
  JackLatencyCallback* = proc (mode: jack_latency_callback_mode; arg: pointer)

## #*
## #  the new latency API operates on Ranges.
## # 

type
  jack_latency_range* = object
    min*: jack_nframes       ## #*
                       ## #      minimum latency
                       ## #     
    ## #*
    ## #      maximum latency
    ## #     
    max*: jack_nframes

## #*
## #  Prototype for the client supplied function that is called
## #  by the engine anytime there is work to be done.
## # 
## #  @pre nframes == jack_get_buffer_size()
## #  @pre nframes == pow(2,x)
## # 
## #  @param nframes number of frames to process
## #  @param arg pointer to a client supplied structure
## # 
## #  @return zero on success, non-zero on error
## # 

type
  JackProcessCallback* = proc (nframes: jack_nframes; arg: pointer): cint

## #*
## #  Prototype for the client thread routine called
## #  by the engine when the client is inserted in the graph.
## # 
## #  @param arg pointer to a client supplied structure
## # 
## # 

type
  JackThreadCallback* = proc (arg: pointer): pointer

## #*
## #  Prototype for the client supplied function that is called
## #  once after the creation of the thread in which other
## #  callbacks will be made. Special thread characteristics
## #  can be set from this callback, for example. This is a
## #  highly specialized callback and most clients will not
## #  and should not use it.
## # 
## #  @param arg pointer to a client supplied structure
## # 
## #  @return void
## # 

type
  JackThreadInitCallback* = proc (arg: pointer)

## #*
## #  Prototype for the client supplied function that is called
## #  whenever the processing graph is reordered.
## # 
## #  @param arg pointer to a client supplied structure
## # 
## #  @return zero on success, non-zero on error
## # 

type
  JackGraphOrderCallback* = proc (arg: pointer): cint

## #*
## #  Prototype for the client-supplied function that is called whenever
## #  an xrun has occured.
## # 
## #  @see jack_get_xrun_delayed_usecs()
## # 
## #  @param arg pointer to a client supplied structure
## # 
## #  @return zero on success, non-zero on error
## # 

type
  JackXRunCallback* = proc (arg: pointer): cint

## #*
## #  Prototype for the @a bufsize_callback that is invoked whenever the
## #  JACK engine buffer size changes.  Although this function is called
## #  in the JACK process thread, the normal process cycle is suspended
## #  during its operation, causing a gap in the audio flow.  So, the @a
## #  bufsize_callback can allocate storage, touch memory not previously
## #  referenced, and perform other operations that are not realtime
## #  safe.
## # 
## #  @param nframes buffer size
## #  @param arg pointer supplied by jack_set_buffer_size_callback().
## # 
## #  @return zero on success, non-zero on error
## # 

type
  JackBufferSizeCallback* = proc (nframes: jack_nframes; arg: pointer): cint

## #*
## #  Prototype for the client supplied function that is called
## #  when the engine sample rate changes.
## # 
## #  @param nframes new engine sample rate
## #  @param arg pointer to a client supplied structure
## # 
## #  @return zero on success, non-zero on error
## # 

type
  JackSampleRateCallback* = proc (nframes: jack_nframes; arg: pointer): cint

## #*
## #  Prototype for the client supplied function that is called
## #  whenever a port is registered or unregistered.
## # 
## #  @param port the ID of the port
## #  @param arg pointer to a client supplied data
## #  @param register non-zero if the port is being registered,
## #                      zero if the port is being unregistered
## # 

type
  JackPortRegistrationCallback* = proc (port: JackPortId; r: cint; arg: pointer)

## #*
## #  Prototype for the client supplied function that is called
## #  whenever a client is registered or unregistered.
## # 
## #  @param name a null-terminated string containing the client name
## #  @param register non-zero if the client is being registered,
## #                      zero if the client is being unregistered
## #  @param arg pointer to a client supplied structure
## # 

type
  JackClientRegistrationCallback* = proc (name: cstring; r: cint; arg: pointer)

## #*
## #  Prototype for the client supplied function that is called
## #  whenever a port is connected or disconnected.
## # 
## #  @param a one of two ports connected or disconnected
## #  @param b one of two ports connected or disconnected
## #  @param connect non-zero if ports were connected
## #                     zero if ports were disconnected
## #  @param arg pointer to a client supplied data
## # 

type
  JackPortConnectCallback* = proc (a: JackPortId; b: JackPortId; connect: cint;
                                arg: pointer)

## #*
## #  Prototype for the client supplied function that is called
## #  whenever the port name has been changed.
## # 
## #  @param port the port that has been renamed
## #  @param new_name the new name
## #  @param arg pointer to a client supplied structure
## # 

type
  JackPortRenameCallback* = proc (port: JackPortId; old_name: cstring;
                               new_name: cstring; arg: pointer)

## #*
## #  Prototype for the client supplied function that is called
## #  whenever jackd starts or stops freewheeling.
## # 
## #  @param starting non-zero if we start starting to freewheel, zero otherwise
## #  @param arg pointer to a client supplied structure
## # 

type
  JackFreewheelCallback* = proc (starting: cint; arg: pointer)

## #*
## #  Prototype for the client supplied function that is called
## #  whenever jackd is shutdown. Note that after server shutdown,
## #  the client pointer is *not* deallocated by libjack,
## #  the application is responsible to properly use jack_client_close()
## #  to release client ressources. Warning: jack_client_close() cannot be
## #  safely used inside the shutdown callback and has to be called outside of
## #  the callback context.
## # 
## #  @param arg pointer to a client supplied structure
## # 

type
  JackShutdownCallback* = proc (arg: pointer)

## #*
## #  Prototype for the client supplied function that is called
## #  whenever jackd is shutdown. Note that after server shutdown,
## #  the client pointer is *not* deallocated by libjack,
## #  the application is responsible to properly use jack_client_close()
## #  to release client ressources. Warning: jack_client_close() cannot be
## #  safely used inside the shutdown callback and has to be called outside of
## #  the callback context.
## #
## #  @param code a status word, formed by OR-ing together the relevant @ref JackStatus bits.
## #  @param reason a string describing the shutdown reason (backend failure, server crash... etc...)
## #  @param arg pointer to a client supplied structure
## # 

type
  JackInfoShutdownCallback* = proc (code: JackStatus; reason: cstring; arg: pointer)

## #*
## #  Used for the type argument of jack_port_register() for default
## #  audio ports and midi ports.
## # 

const
  JACK_DEFAULT_AUDIO_TYPE* = "32 bit float mono audio".cstring
  JACK_DEFAULT_MIDI_TYPE* = "8 bit raw midi".cstring

## #*
## #  For convenience, use this typedef if you want to be able to change
## #  between float and double. You may want to typedef sample to
## #  jack_default_audio_sample in your application.
## # 

type
  jack_default_audio_sample* = cfloat

## #*
## #   A port has a set of flags that are formed by AND-ing together the
## #   desired values from the list below. The flags "JackPortIsInput" and
## #   "JackPortIsOutput" are mutually exclusive and it is an error to use
## #   them both.
## # 

type
  JackPortFlags* = enum ## #*
                     ## #      if JackPortIsInput is set, then the port can receive
                     ## #      data.
                     ## #     
    JackPortIsInput = 0x00000001, ## #*
                               ## #      if JackPortIsOutput is set, then data can be read from
                               ## #      the port.
                               ## #     
    JackPortIsOutput = 0x00000002, ## #*
                                ## #      if JackPortIsPhysical is set, then the port corresponds
                                ## #      to some kind of physical I/O connector.
                                ## #     
    JackPortIsPhysical = 0x00000004, ## #*
                                  ## #      if JackPortCanMonitor is set, then a call to
                                  ## #      jack_port_request_monitor() makes sense.
                                  ## #     
                                  ## #      Precisely what this means is dependent on the client. A typical
                                  ## #      result of it being called with TRUE as the second argument is
                                  ## #      that data that would be available from an output port (with
                                  ## #      JackPortIsPhysical set) is sent to a physical output connector
                                  ## #      as well, so that it can be heard/seen/whatever.
                                  ## #     
                                  ## #      Clients that do not control physical interfaces
                                  ## #      should never create ports with this bit set.
                                  ## #     
    JackPortCanMonitor = 0x00000008, ## #*
                                  ## #      JackPortIsTerminal means:
                                  ## #     
                                  ## #       for an input port: the data received by the port
                                  ## #                         will not be passed on or made
                                  ## #                          available at any other port
                                  ## #     
                                  ## #      for an output port: the data available at the port
                                  ## #                         does not originate from any other port
                                  ## #     
                                  ## #      Audio synthesizers, I/O hardware interface clients, HDR
                                  ## #      systems are examples of clients that would set this flag for
                                  ## #      their ports.
                                  ## #     
    JackPortIsTerminal = 0x00000010


## #*
## #  Transport states.
## # 

type                          ## # the order matters for binary compatibility 
  jack_transport_state* = enum
    JackTransportStopped = 0,   ## #*< Transport halted 
    JackTransportRolling = 1,   ## #*< Transport playing 
    JackTransportLooping = 2,   ## #*< For OLD_TRANSPORT, now ignored 
    JackTransportStarting = 3,  ## #*< Waiting for sync ready 
    JackTransportNetStarting = 4 ## #*< Waiting for sync ready on the network
  jack_unique* = uint64


## #*< Unique ID (opaque) 
## #*
## #  Optional struct jack_position fields.
## # 

type
  jack_position_bits* = enum
    JackPositionBBT = 0x00000010, ## #*< Bar, Beat, Tick 
    JackPositionTimecode = 0x00000020, ## #*< External timecode 
    JackBBTFrameOffset = 0x00000040, ## #*< Frame offset of BBT information 
    JackAudioVideoRatio = 0x00000080, ## #*< audio frames per video frame 
    JackVideoFrameOffset = 0x00000100


converter toInt(x: jack_position_bits): int =
  result = x.int

## #* all valid position bits 

const
  JACK_POSITION_MASK* = (JackPositionBBT or JackPositionTimecode)
  EXTENDED_TIME_INFO* = true

type
  jack_position* = object
    unique_1*: jack_unique   ## # these four cannot be set from clients: the server sets them 
    ## #*< unique ID 
    usecs*: jack_time        ## #*< monotonic, free-rolling 
    frame_rate*: jack_nframes ## #*< current frame rate (per second) 
    frame*: jack_nframes     ## #*< frame number, always present 
    valid*: jack_position_bits ## #*< which other fields are valid 
                               ## # JackPositionBBT fields: 
    bar*: int32              ## #*< current bar 
    beat*: int32             ## #*< current beat-within-bar 
    tick*: int32             ## #*< current tick-within-beat 
    bar_start_tick*: cdouble
    beats_per_bar*: cfloat     ## #*< time signature "numerator" 
    beat_type*: cfloat         ## #*< time signature "denominator" 
    ticks_per_beat*: cdouble
    beats_per_minute*: cdouble ## # JackPositionTimecode fields:     (EXPERIMENTAL: could change) 
    frame_time*: cdouble       ## #*< current time in seconds 
    next_time*: cdouble        ## #*< next sequential frame_time
                      ## #                         (unless repositioned) 
                      ## # JackBBTFrameOffset fields: 
    bbt_offset*: jack_nframes ## #*< frame offset for the BBT fields
                              ## #                         (the given bar, beat, and tick
                              ## #                         values actually refer to a time
                              ## #                         frame_offset frames before the
                              ## #                         start of the cycle), should
                              ## #                         be assumed to be 0 if
                              ## #                         JackBBTFrameOffset is not
                              ## #                         set. If JackBBTFrameOffset is
                              ## #                         set and this value is zero, the BBT
                              ## #                         time refers to the first frame of this
                              ## #                         cycle. If the value is positive,
                              ## #                         the BBT time refers to a frame that
                              ## #                         many frames before the start of the
                              ## #                         cycle. 
                              ## # JACK video positional data (experimental) 
    audio_frames_per_video_frame*: cfloat ## #*< number of audio frames
                                        ## #                         per video frame. Should be assumed
                                        ## #                         zero if JackAudioVideoRatio is not
                                        ## #                         set. If JackAudioVideoRatio is set
                                        ## #                         and the value is zero, no video
                                        ## #                         data exists within the JACK graph 
    video_offset*: jack_nframes ## #*< audio frame at which the first video
                                ## #                         frame in this cycle occurs. Should
                                ## #                         be assumed to be 0 if JackVideoFrameOffset
                                ## #                         is not set. If JackVideoFrameOffset is
                                ## #                         set, but the value is zero, there is
                                ## #                         no video frame within this cycle. 
                                ## # For binary compatibility, new fields should be allocated from
                                ## #      this padding area with new valid bits controlling access, so
                                ## #      the existing structure size and offsets are preserved. 
    padding*: array[7, int32] ## # When (unique_1 == unique_2) the contents are consistent. 
    unique_2*: jack_unique   ## #*< unique ID 

## #*
## #     Prototype for the @a sync_callback defined by slow-sync clients.
## #     When the client is active, this callback is invoked just before
## #     process() in the same thread.  This occurs once after registration,
## #     then subsequently whenever some client requests a new position, or
## #     the transport enters the ::JackTransportStarting state.  This
## #     realtime function must not wait.
## #    
## #     The transport @a state will be:
## #    
## #       - ::JackTransportStopped when a new position is requested;
## #       - ::JackTransportStarting when the transport is waiting to start;
## #       - ::JackTransportRolling when the timeout has expired, and the
## #       position is now a moving target.
## #    
## #     @param state current transport state.
## #     @param pos new transport position.
## #     @param arg the argument supplied by jack_set_sync_callback().
## #    
## #     @return TRUE (non-zero) when ready to roll.
## #    

type
  JackSyncCallback* = proc (state: jack_transport_state; pos: ptr jack_position;
                         arg: pointer): cint

## #*
## #   Prototype for the @a timebase_callback used to provide extended
## #   position information.  Its output affects all of the following
## #   process cycle.  This realtime function must not wait.
## #  
## #   This function is called immediately after process() in the same
## #   thread whenever the transport is rolling, or when any client has
## #   requested a new position in the previous cycle.  The first cycle
## #   after jack_set_timebase_callback() is also treated as a new
## #   position, or the first cycle after jack_activate() if the client
## #   had been inactive.
## #  
## #   The timebase master may not use its @a pos argument to set @a
## #   pos->frame.  To change position, use jack_transport_reposition() or
## #   jack_transport_locate().  These functions are realtime-safe, the @a
## #   timebase_callback can call them directly.
## #  
## #   @param state current transport state.
## #   @param nframes number of frames in current period.
## #   @param pos address of the position structure for the next cycle; @a
## #   pos->frame will be its frame number.  If @a new_pos is FALSE, this
## #   structure contains extended position information from the current
## #   cycle.  If TRUE, it contains whatever was set by the requester.
## #   The @a timebase_callback's task is to update the extended
## #   information here.
## #   @param new_pos TRUE (non-zero) for a newly requested @a pos, or for
## #   the first cycle after the @a timebase_callback is defined.
## #   @param arg the argument supplied by jack_set_timebase_callback().
## #  

type
  JackTimebaseCallback* = proc (state: jack_transport_state;
                             nframes: jack_nframes; pos: ptr jack_position;
                             new_pos: cint; arg: pointer)

## #********************************************************************
## #     The following interfaces are DEPRECATED.  They are only provided
## #     for compatibility with the earlier JACK transport implementation.
## #    *******************************************************************
## #*
## #  Optional struct jack_transport_info fields.
## # 
## #  @see jack_position_bits.
## # 

type
  jack_transport_bits* = enum
    JackTransportState = 0x00000001, ## #*< Transport state 
    JackTransportPosition = 0x00000002, ## #*< Frame number 
    JackTransportLoop = 0x00000004, ## #*< Loop boundaries (ignored) 
    JackTransportSMPTE = 0x00000008, ## #*< SMPTE (ignored) 
    JackTransportBBT = 0x00000010


## #*
## #  Deprecated struct for transport position information.
## # 
## #  @deprecated This is for compatibility with the earlier transport
## #  interface.  Use the jack_position struct, instead.
## # 

type
  jack_transport_info* = object
    frame_rate*: jack_nframes ## # these two cannot be set from clients: the server sets them 
    ## #*< current frame rate (per second) 
    usecs*: jack_time        ## #*< monotonic, free-rolling 
    valid*: jack_transport_bits ## #*< which fields are legal to read 
    transport_state*: jack_transport_state
    frame*: jack_nframes
    loop_start*: jack_nframes
    loop_end*: jack_nframes
    smpte_offset*: clong       ## #*< SMPTE offset (from frame 0) 
    smpte_frame_rate*: cfloat  ## #*< 29.97, 30, 24 etc. 
    bar*: cint
    beat*: cint
    tick*: cint
    bar_start_tick*: cdouble
    beats_per_bar*: cfloat
    beat_type*: cfloat
    ticks_per_beat*: cdouble
    beats_per_minute*: cdouble

