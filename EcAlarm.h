
/** Enterprise Control Configuration and Logging

   Copyright (C) 2012 Free Software Foundation, Inc.

   Written by: Richard Frith-Macdonald <rfm@gnu.org>
   Date: Febrary 2010
   Originally developed from 1996 to 2012 by Brainstorm, and donated to
   the FSF.

   This file is part of the GNUstep project.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 3 of the License, or (at your option) any later version.

   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Library General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with this library; if not, write to the Free
   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
   Boston, MA 02111 USA.

   */

#ifndef	_ECALARM_H
#define	_ECALARM_H

#import <Foundation/NSObject.h>

@class	NSCoder;
@class	NSDate;
@class	NSDictionary;
@class	NSString;

/**
 * The EcAlarmEventType enumeration defines the different types of
 * alarm we support.<br />
 * The enumerated values MUST be matched by those in your SNMP MIB if
 * you wish to have your software interact with SNMP tools.<br />
 * NB. EcAlarmEventTypeUnknown must <em>NOT</em> be used in an alarm ...
 * it is employed solely as a marker for the case where a lookup of
 * type from probable cause can not determine a specific event type.
 * <deflist>
 *   <term>EcAlarmEventTypeUnknown</term>
 *   <desc>Not used</desc>
 *   <term>EcAlarmEventTypeCommunications</term>
 *   <desc>A communications/networking/protocol issue</desc>
 *   <term>EcAlarmEventTypeEnvironmental</term>
 *   <desc>An external environmental issue (eg building on fire)</desc>
 *   <term>EcAlarmEventTypeEquipment</term>
 *   <desc>A hardware problem (eg disk failure)</desc>
 *   <term>EcAlarmEventTypeProcessingError</term>
 *   <desc>A software problem (a bug or misconfiguration)</desc>
 *   <term>EcAlarmEventTypeQualityOfService</term>
 *   <desc>A system not running as well as expected ... eg. overloaded</desc>
 * </deflist>
 */
typedef enum {
  EcAlarmEventTypeUnknown = 0,
  EcAlarmEventTypeCommunications = 2,
  EcAlarmEventTypeEnvironmental = 3,
  EcAlarmEventTypeEquipment = 4,
  EcAlarmEventTypeProcessingError = 10,
  EcAlarmEventTypeQualityOfService = 11,
} EcAlarmEventType;

/** The EcAlarmProbableCause enumeration defines the probable causes of
 * alarms produced by the system.<br />
 * These are taken from the CCITT X.733 specification with the numeric
 * values from the CCITT X.721 specification.<br />
 * Enumeration values include a comment to specify which
 * EcAlarmEventType they apply to.
 * <deflist>
 *   <term>EcAlarmProbableCauseUnknown</term>
 *   <desc>Category: Any</desc>
 *   <term>EcAlarmAdapterError</term>
 *   <desc>Category: Equipment</desc>
 *   <term>EcAlarmApplicationSubsystemFailure</term>
 *   <desc>Category: Processing</desc>
 *   <term>EcAlarmBandwidthReduced</term>
 *   <desc>Category: QoS</desc>
 *   <term>EcAlarmCallEstablishmentError</term>
 *   <desc>Category: Communications</desc>
 *   <term>EcAlarmCommunicationsProtocolError</term>
 *   <desc>Category: Communications</desc>
 *   <term>EcAlarmCommunicationsSubsystemFailure</term>
 *   <desc>Category: Communications</desc>
 *   <term>EcAlarmConfigurationOrCustomizationError</term>
 *   <desc>Category: Processing</desc>
 *   <term>EcAlarmCongestion</term>
 *   <desc>Category: QoS</desc>
 *   <term>EcAlarmCorruptData</term>
 *   <desc>Category: Processing</desc>
 *   <term>EcAlarmCpuCyclesLimitExceeded</term>
 *   <desc>Category: Processing</desc>
 *   <term>EcAlarmDataSetOrModemError</term>
 *   <desc>Category: Equipment</desc>
 *   <term>EcAlarmDegradedSignal</term>
 *   <desc>Category: Communications</desc>
 *   <term>EcAlarmDTE_DCEInterfaceError</term>
 *   <desc>Category: Communications</desc>
 *   <term>EcAlarmEnclosureDoorOpen</term>
 *   <desc>Category: Environmental</desc>
 *   <term>EcAlarmEquipmentMalfunction</term>
 *   <desc>Category: Equipment</desc>
 *   <term>EcAlarmExcessiveVibration</term>
 *   <desc>Category: Environmental</desc>
 *   <term>EcAlarmFileError</term>
 *   <desc>Category: Processing</desc>
 *   <term>EcAlarmFireDetected</term>
 *   <desc>Category: Environmental</desc>
 *   <term>EcAlarmFloodDetected</term>
 *   <desc>Category: Environmental</desc>
 *   <term>EcAlarmFramingError</term>
 *   <desc>Category: Communications</desc>
 *   <term>EcAlarmHeatingOrVentilationOrCoolingSystemProblem</term>
 *   <desc>Category: Environmental</desc>
 *   <term>EcAlarmHumidityUnacceptable</term>
 *   <desc>Category: Environmental</desc>
 *   <term>EcAlarmInputOutputDeviceError</term>
 *   <desc>Category: Equipment</desc>
 *   <term>EcAlarmInputDeviceError</term>
 *   <desc>Category: Equipment</desc>
 *   <term>EcAlarmLANError</term>
 *   <desc>Category: Communications</desc>
 *   <term>EcAlarmLeakDetected</term>
 *   <desc>Category: Environmental</desc>
 *   <term>EcAlarmLocalNodeTransmissionError</term>
 *   <desc>Category: Communications</desc>
 *   <term>EcAlarmLossOfFrame</term>
 *   <desc>Category: Communications</desc>
 *   <term>EcAlarmLossOfSignal</term>
 *   <desc>Category: Communications</desc>
 *   <term>EcAlarmMaterialSupplyExhausted</term>
 *   <desc>Category: Environmental</desc>
 *   <term>EcAlarmMultiplexerProblem</term>
 *   <desc>Category: Equipment</desc>
 *   <term>EcAlarmOutOfMemory</term>
 *   <desc>Category: Processing</desc>
 *   <term>EcAlarmOutputDeviceError</term>
 *   <desc>Category: Equipment</desc>
 *   <term>EcAlarmPerformanceDegraded</term>
 *   <desc>Category: QoS</desc>
 *   <term>EcAlarmPowerProblem</term>
 *   <desc>Category: Equipment</desc>
 *   <term>EcAlarmPressureUnacceptable</term>
 *   <desc>Category: Environmental</desc>
 *   <term>EcAlarmProcessorProblem</term>
 *   <desc>Category: Equipment</desc>
 *   <term>EcAlarmPumpFailure</term>
 *   <desc>Category: Environmental</desc>
 *   <term>EcAlarmQueueSizeExceeded</term>
 *   <desc>Category: QoS</desc>
 *   <term>EcAlarmReceiveFailure</term>
 *   <desc>Category: Equipment</desc>
 *   <term>EcAlarmReceiverFailure</term>
 *   <desc>Category: Equipment</desc>
 *   <term>EcAlarmRemoteNodeTransmissionError</term>
 *   <desc>Category: Communications</desc>
 *   <term>EcAlarmResourceAtOrNearingCapacity</term>
 *   <desc>Category: QoS</desc>
 *   <term>EcAlarmResponseTimeExcessive</term>
 *   <desc>Category: QoS</desc>
 *   <term>EcAlarmRetransmissionRateExcessive</term>
 *   <desc>Category: QoS</desc>
 *   <term>EcAlarmSoftwareProgramAbnormallyTerminated</term>
 *   <desc>Category: Processing</desc>
 *   <term>EcAlarmSoftwareProgramError</term>
 *   <desc>Category: Processing</desc>
 *   <term>EcAlarmStorageCapacityProblem</term>
 *   <desc>Category: Processing</desc>
 *   <term>EcAlarmTemperatureUnacceptable</term>
 *   <desc>Category: Environmental</desc>
 *   <term>EcAlarmThresholdCrossed</term>
 *   <desc>Category: QoS</desc>
 *   <term>EcAlarmTimingProblem</term>
 *   <desc>Category: Equipment</desc>
 *   <term>EcAlarmToxicLeakDetected</term>
 *   <desc>Category: Environmental</desc>
 *   <term>EcAlarmTransmitFailure</term>
 *   <desc>Category: Equipment</desc>
 *   <term>EcAlarmTransmitterFailure</term>
 *   <desc>Category: Equipment</desc>
 *   <term>EcAlarmUnderlyingResourceUnavailable</term>
 *   <desc>Category: Processing</desc>
 *   <term>EcAlarmVersionMismatch</term>
 *   <desc>Category: Processing</desc>
 * </deflist>
 */
typedef enum {
  EcAlarmProbableCauseUnknown = 0,			// Any

  EcAlarmAdapterError = 1,				// Equipment
  EcAlarmApplicationSubsystemFailure = 2,		// Processing
  EcAlarmBandwidthReduced = 3,				// QoS
  EcAlarmCallEstablishmentError = 4,			// Communications
  EcAlarmCommunicationsProtocolError = 5,		// Communications
  EcAlarmCommunicationsSubsystemFailure = 6,		// Communications
  EcAlarmConfigurationOrCustomizationError = 7,		// Processing
  EcAlarmCongestion = 8,				// QoS
  EcAlarmCorruptData = 9,				// Processing
  EcAlarmCpuCyclesLimitExceeded = 10,			// Processing
  EcAlarmDataSetOrModemError = 11,			// Equipment
  EcAlarmDegradedSignal = 12,				// Communications
  EcAlarmDTE_DCEInterfaceError = 13,			// Communications
  EcAlarmEnclosureDoorOpen = 14,			// Environmental
  EcAlarmEquipmentMalfunction = 15,			// Equipment
  EcAlarmExcessiveVibration = 16,			// Environmental
  EcAlarmFileError = 17,				// Processing
  EcAlarmFireDetected = 18,				// Environmental
  EcAlarmFloodDetected = 19,				// Environmental
  EcAlarmFramingError = 20,				// Communications
  EcAlarmHeatingOrVentilationOrCoolingSystemProblem = 21,	// Environmental
  EcAlarmHumidityUnacceptable = 22,			// Environmental
  EcAlarmInputOutputDeviceError = 23,			// Equipment
  EcAlarmInputDeviceError = 24,				// Equipment
  EcAlarmLANError = 25,					// Communications
  EcAlarmLeakDetected = 26,				// Environmental
  EcAlarmLocalNodeTransmissionError = 27,		// Communications
  EcAlarmLossOfFrame = 28,				// Communications
  EcAlarmLossOfSignal = 29,				// Communications
  EcAlarmMaterialSupplyExhausted = 30,			// Environmental
  EcAlarmMultiplexerProblem = 31,			// Equipment
  EcAlarmOutOfMemory = 32,				// Processing
  EcAlarmOutputDeviceError = 33,			// Equipment
  EcAlarmPerformanceDegraded = 34,			// QoS
  EcAlarmPowerProblem = 35,				// Equipment
  EcAlarmPressureUnacceptable = 36,			// Environmental
  EcAlarmProcessorProblem = 37,				// Equipment
  EcAlarmPumpFailure = 38,				// Environmental
  EcAlarmQueueSizeExceeded = 39,			// QoS
  EcAlarmReceiveFailure = 40,				// Equipment
  EcAlarmReceiverFailure = 41,				// Equipment
  EcAlarmRemoteNodeTransmissionError = 42,		// Communications
  EcAlarmResourceAtOrNearingCapacity = 43,		// QoS
  EcAlarmResponseTimeExcessive = 44,			// QoS
  EcAlarmRetransmissionRateExcessive = 45,		// QoS
  EcAlarmSoftwareProgramAbnormallyTerminated = 47,	// Processing
  EcAlarmSoftwareProgramError = 48,			// Processing
  EcAlarmStorageCapacityProblem = 49,			// Processing
  EcAlarmTemperatureUnacceptable = 50,			// Environmental
  EcAlarmThresholdCrossed = 51,				// QoS
  EcAlarmTimingProblem = 52,				// Equipment
  EcAlarmToxicLeakDetected = 53,			// Environmental
  EcAlarmTransmitFailure = 54,				// Equipment
  EcAlarmTransmitterFailure = 55,			// Equipment
  EcAlarmUnderlyingResourceUnavailable = 56,		// Processing
  EcAlarmVersionMismatch = 57,				// Processing

} EcAlarmProbableCause;

/** The EcAlarmSeverity enumeration defines the 'perceived severities' of
 * alarms produced by the system.<br />
 * The enumerated values MUST be matched by those in your SNMP MIB if
 * you wish to have your software interact with SNMP tools.<br />
 * NB. The use of EcAlarmSeverityIndeterminate should be avoided.
 * <deflist>
 *   <term>EcAlarmSeverityIndeterminate</term><desc>Do not use</desc>
 *   <term>EcAlarmSeverityCritical</term>
 *   <desc>Immediate intervention required to restore service</desc>
 *   <term>EcAlarmSeverityMajor</term>
 *   <desc>Severe but partial system failure or a problem which
 *   might recover without intervention</desc>
 *   <term>EcAlarmSeverityMinor</term>
 *   <desc>A failure, but one which is likely to recover or which is
 *   probably not urgent</desc>
 *   <term>EcAlarmSeverityWarning</term>
 *   <desc>An unusual event which may not indicate any problem, but
 *   which ought to be looked into</desc>
 *   <term>EcAlarmSeverityCleared</term>
 *   <desc>This indicates the resolution of an earlier issue</desc>
 * </deflist>
 */
typedef enum {
  EcAlarmSeverityIndeterminate = 0,
  EcAlarmSeverityCritical = 1,
  EcAlarmSeverityMajor = 2,
  EcAlarmSeverityMinor = 3,
  EcAlarmSeverityWarning = 4,
  EcAlarmSeverityCleared = 5
} EcAlarmSeverity;

/** The EcAlarmTrend enumeration defines the severity trend of alarms
 * produced by the system.<br />
 * The enumerated values MUST be matched by those in your SNMP MIB if
 * you wish to have your software interact with SNMP tools.<br />
 * <deflist>
 *   <term>EcAlarmTrendNone</term>
 *   <desc>This is not a change in severity of an earlier alarm</desc>
 *   <term>EcAlarmTrendUp</term>
 *   <desc>This is a more severe version of an earlier alarm</desc>
 *   <term>EcAlarmTrendDown</term>
 *   <desc>This is a less severe version of an earlier alarm</desc>
 * </deflist>
 */
typedef enum {
  EcAlarmTrendNone = 0,
  EcAlarmTrendUp = '+',
  EcAlarmTrendDown = '-',
} EcAlarmTrend;

/** This function builds a managed object name from host, process,
 * and component.<br />
 * The host part may be nil ... for the current host.<br />
 * The process part may be nil ... for the current process.<br />
 * The component may well be nil if the alert applies to the process as
 * a whole rather than to a particular component.  This field is typically
 * used to identify a particular network connection etc within a process.<br />
 * This parses the process and separates out any instance ID (trailing
 * hyphen and string of digits).  It then builds the managed object from
 * four parts (host, process, instance, component) separated by underscores.
 * Any underscores in the arguments are replaced by hyphens.<br />
 * NB. The total length must not exceed 127 ASCII characters.
 */
NSString *
EcMakeManagedObject(NSString *host, NSString *process, NSString *component);
 
/** <p>The EcAlarm class encapsulates an alarm to be sent out to a monitoring
 * system.  It's designed to work cleanly with industry standard SNMP
 * alarm monitoring systems.  For more information on how the SNMP
 * operation works, see the [EcAlarmSinkSNMP] class documentation.
 * </p>
 * <p>Instances are created and sent to a central coordination point
 * where checks are performed to see if there is an existing alarm for
 * the same issue.  If the incoming alarm does not change the severity
 * of an existing alarm, it is ignored, otherwise it may be passed on to
 * an external monitoring system.  The central coordination system is
 * responsible for ensuring that alarms for the same issue are updated
 * to contain the first event date, notification ID and a trend indicator.
 * </p>
 */
@interface	EcAlarm : NSObject <NSCoding,NSCopying>
{
  NSString		*_managedObject;
  NSDate		*_eventDate;
  NSDate		*_firstEventDate;
  EcAlarmEventType	_eventType;
  EcAlarmSeverity	_perceivedSeverity;
  EcAlarmProbableCause	_probableCause;
  NSString		*_specificProblem;
  NSString		*_proposedRepairAction;
  NSString		*_additionalText;
  EcAlarmTrend		_trendIndicator;
  int			_notificationID;
  NSDictionary          *_userInfo;
  void			*_extra;
  BOOL			_frozen;
  uint8_t               _delay;
}

/** Creates and returns an autoreleased instance by calling the
 * designated initialiser with all the supplied arguments.
 */
+ (EcAlarm*) alarmForManagedObject: (NSString*)managedObject
				at: (NSDate*)eventDate
		     withEventType: (EcAlarmEventType)eventType
		     probableCause: (EcAlarmProbableCause)probableCause
		   specificProblem: (NSString*)specificProblem
		 perceivedSeverity: (EcAlarmSeverity)perceivedSeverity
	      proposedRepairAction: (NSString*)proposedRepairAction
		    additionalText: (NSString*)additionalText;

/** This method provides a mapping from the probable cause of an event to
 * the event type.<br />
 * The method is called during initialisation of an alarm instance (except
 * where the probable cause is EcAlarmProbableCauseUnknown) to check that the
 * supplied arguments are consistent. If a subclass extends the possible
 * probable cause values, it must also override this method to handle those
 * new values by returning a known event type.
 */
+ (EcAlarmEventType) eventTypeFromProbableCause: (EcAlarmProbableCause)value;

/** Provides a human readable string representation of an event type.<br />
 * This method is called during initialisation of an alarm instance to check
 * that the supplied event type is legal.<br />
 * Returns nil if the value is unknown.<br />
 */
+ (NSString*) stringFromEventType: (EcAlarmEventType)value;

/** Provides a human readable string representation of a probable cause.<br />
 * Returns nil if the value is unknown.
 */
+ (NSString*) stringFromProbableCause: (EcAlarmProbableCause)value;

/** Provides a human readable string representation of a severity.<br />
 * Returns nil if the value is unknown.
 */
+ (NSString*) stringFromSeverity: (EcAlarmSeverity)value;

/** Provides a human readable string representation of a trend.<br />
 * Returns nil if the value is unknown.
 */
+ (NSString*) stringFromTrend: (EcAlarmTrend)value;


/** This is the supplementary text (optional) which may be provided with
 * and alarm an an aid to the human operator for the monitoring system.
 */
- (NSString*) additionalText;

/** Compares the other object with the receiver for sorting/ordering.<br />
 * If both objects have a notificationID set then the result of the
 * numeric comparison of those IDs is used.<br />
 * Otherwise the result of the comparison orders the objects by
 * managedObject, eventType, probableCause, and specificProblem.
 */
- (NSComparisonResult) compare: (EcAlarm*)other;

/** Returns an autoreleased copy of the receiver with the same notificationID
 * but with a perceivedSeverity set to be EcAlarmSeverityCleared ... this may
 * be used to clear the alarm represented by the receiver.
 */
- (EcAlarm*) clear;

/** EcAlarm objects may be copied.  This method is provided to implement
 * the NSCopying protocol.<br />
 * A copy of an object does <em>not</em> copy any value provided by the
 * -setExtra: method.<br />
 * A copy of an object is not frozen.
 */
- (id) copyWithZone: (NSZone*)aZone;

/** Deallocates the receiver.
 */
- (void) dealloc;

/** Returns the queue delay set for this alarm (or zero if none was set).
 */
- (uint8_t) delay;

/** Returns YES if the receiver should be delayed in the queue past the
 * supplied timestamp, NO otherwise.
 */
- (BOOL) delayed: (NSTimeInterval)at;

/** EcAlarm objects may be passed over the distributed objects system or
 * archived.  This method is provided to implement the NSCoding protocol.<br />
 * An encoded copy of an object does <em>not</em> copy any value provided
 * by the -setExtra: method.
 */
- (void) encodeWithCoder: (NSCoder*)aCoder;

/** Returns the timestamp of the event which generated the alarm.
 */
- (NSDate*) eventDate;

/** This method returns the type for event which generated the alarm.
 */
- (EcAlarmEventType) eventType;

/** Returns any extra information stored by the -setExtra: method.<br />
 */
- (void*) extra;

/** If this alarm is known to be represent an event updating the status of
 * an existing alarm, this method returns the date of the initial event.
 * otherwise it returns nil.
 */
- (NSDate*) firstEventDate;

/** Freeze the state of the receiver;
 * no more calls to setters are permitted.<br />
 * Then a frozen alarm is copied, the new copy is <em>not</em> frozen.
 */
- (void) freeze;

/** Returns the hash of the receiver ... which is also the hash of its
 * managedObject.
 */
- (NSUInteger) hash;

/** <init/>
 * Initialises the receiver as an alarm for a particular event.<br />
 * The managedObject argument may be nil if the alarm should use the
 * default managed object value for the current process.<br />
 * The eventDate argument may be nil if the alarm should use the current
 * timestamp.<br />
 * The managedObject, eventType, probableCause, and specificProblem
 * arguments uniquely identify the issue for which an alarm is being
 * produced.<br />
 * The perceivedSeverity indicates the importance of the problem, with a
 * value of EcAlarmSeverityCleared indicating that the problem is over.<br />
 * A proposedRepairAction is mandatory (unless the severity is cleared)
 * to provide the human operator with some sort of hint about how they
 * should resolve the issue.
 */
- (id) initForManagedObject: (NSString*)managedObject
			 at: (NSDate*)eventDate
	      withEventType: (EcAlarmEventType)eventType
	      probableCause: (EcAlarmProbableCause)probableCause
	    specificProblem: (NSString*)specificProblem
	  perceivedSeverity: (EcAlarmSeverity)perceivedSeverity
       proposedRepairAction: (NSString*)proposedRepairAction
	     additionalText: (NSString*)additionalText;

/** EcAlarm objects may be passed over the distributed objects system or
 * archived.  This method is provided to implement the NSCoding protocol.
 */
- (id) initWithCoder: (NSCoder*)aCoder;

/** Returns a flag indicating whether the receiver is equal to the other
 * object. To be considered equal either:<br />
 * The two objects must have equal managedObject values and equal (non-zero)
 * notificationID values or<br />
 * the two objects must have equal managedObject values,
 * equal eventType values, equal probableCause values,
 * and equal specificProblem values.<br />
 * NB. you must not set two alarm instances to have the same notificationID
 * values if they are not considered equal using the other criteria.
 */
- (BOOL) isEqual: (id)other;

/** Returns the managedObject value set when the receiver was initialised.
 */
- (NSString*) managedObject;

/** Returns the component of the managed object (if any).
 */
- (NSString*) moComponent;

/** Returns the host of the managed object.
 */
- (NSString*) moHost;

/** Returns the instance of the managed object (if any).
 */
- (NSString*) moInstance;

/** Returns the process name of the managed object.
 */
- (NSString*) moProcess;

/** Returns zero or the notificationID value most recently set by
 * the -setNotificationID: method.
 */
- (int) notificationID;

/** Returns the perceivedSeverity set when the receiver was initialised.
 */
- (EcAlarmSeverity) perceivedSeverity;

/** Returns the proposedRepairAction set when the receiver was initialised.
 */
- (NSString*) proposedRepairAction;

/** Returns the probableCause set when the receiver was initialised.
 */
- (EcAlarmProbableCause) probableCause;

/** Sets the number of seconds for which this alarm should be delayed in the
 * queue to allow coalescing with other matching alarms.  This defaults to
 * zero so that there is no special delay in processing beyond that imposed
 * by periodic queue flushing.
 */
- (void) setDelay: (uint8_t)delay;

/** Sets extra data for the current instance.<br />
 * Extra data is not copied, archived, or transferred over DO, it is available
 * only in the exact instance of the class in which it was set.
 */
- (void) setExtra: (void*)extra;

/** Sets the first event date for the receiver.<br />
 * You should not normally call this as it is reserved for use by code
 * which has matched the receiver to an existing alarm.
 */
- (void) setFirstEventDate: (NSDate*)firstEventDate;

/** Sets the notification ID for the receiver.<br />
 * You should not normally call this as it is reserved for use by code
 * which has matched the receiver to an existing alarm.<br />
 * In particular, two instances should not be set to have the same non-zero
 * notificationID unless they are equal according to other criteria of
 * equality (ie have the same managedObject, eventType, probableCause,
 * and specificProblem values).
 */
- (void) setNotificationID: (int)notificationID;

/** Sets the trend indicator for the receiver.<br />
 * You should not normally call this as it is reserved for use by code
 * which has matched the receiver to an existing alarm.
 */
- (void) setTrendIndicator: (EcAlarmTrend)trendIndicator;

/** Sets the user information associated with this alarm (a dictionary).<br />
 * This user information is additional data associated with the alarm
 * which is copied when the alarm is copied.  This data is not used by
 * the CCITT X.733 ... it's optional additional data.<br />
 * Conventional keys are:<br />
 * <deflist>
 *   <term>ResponsibleEmail</term>
 *   <desc>The Email address of the person/entity with primary responsibility
 *   for dealing with an alarm ... this is intended for use by the alerting
 *   system (EcAlerter) when deciding where to send email alerts.
 *   </desc>
 * </deflist>
 */
- (void) setUserInfo: (NSDictionary*)userInfo;

/** Returns the specificProblem set when the receiver was initialised.
 */
- (NSString*) specificProblem;

/** Returns the value most recently set by the -setTrendIndicator: method
 * (or EcAlarmTrendNone if that method has not been called).<br />
 * This tells you whether the receiver represents an increase in severity
 * of an issue, or a decrease in severity (or no change).
 */
- (EcAlarmTrend) trendIndicator;

/** Returns any previously set information (see -setUserInfo:) or nil
 * if none has been set.
 */
- (NSDictionary*) userInfo;
@end

@interface	EcAlarm (Convenience)

/** Generates an alarm to clears an alarm previously generated.<br />
 * The componentName may be nil for a process-wide alarm.<br />
 * The probableCause must NOT be unknown ... it is used to infer
 * the event type.<br />
 * The specificProblem must be identical to the value supplied in the
 * original alarm that this is intended to clear.
 */
+ (EcAlarm*) clear: (NSString*)componentName
	     cause: (EcAlarmProbableCause)probableCause
	   problem: (NSString*)specificProblem;
		

/** Generates a new alarm event with minimal parameters.<br />
 * The componentName may be nil for a process-wide alarm.<br />
 * The probableCause must NOT be unknown ... it is used to infer
 * the event type.<br />
 * The specificProblem is used to identify the event for which the
 * alarm is raised.<br />
 * The perceivedSeverity must be one of EcAlarmSeverityWarning,
 * EcAlarmSeverityMinor, EcAlarmSeverityMajor or EcAlarmSeverityCritical.<br />
 * The proposedRepairAction must contain information sufficient
 * for any person receiving notification of the alarm to be able
 * to deal with it.  The action is a format string, optionally
 * followed by any number of arguments to be incorporated into
 * the repair action. NB. The resulting proposed repair action
 * must be no more than 255 bytes in length when converted to
 * UTF-8 data.
 */
+ (EcAlarm*) raise: (NSString*)componentName
	     cause: (EcAlarmProbableCause)probableCause
	   problem: (NSString*)specificProblem
	  severity: (EcAlarmSeverity)perceivedSeverity
	    action: (NSString*)proposedRepairAction, ...;

@end

#endif

