spawn = require('child_process').spawn
punctual = require 'punctual'
Event = require('./event').Event

class EventScheduler
	constructor: (@logger, @redisClient, maxRetain) ->
		@maxRetain = maxRetain || 3600
		@taskDAO = punctual.TaskDAO.create({
			redisClient: @redisClient,
			redisKeys: {
        		scheduledJobsZset: 'pushMessage:scheduler',
        		scheduledJobsHash: (jobId) -> 
        			return 'pushMessage:scheduler:' + jobId.toString()
    		}
		})

	taskFromMessage: (event, message) ->
		at = +message.at
		scheduledFor = new Date(1000 * at)
		atTheLatest = at + @maxRetain
		if message.atTheLatest? && +(message.atTheLatest)
			atTheLatest = +message.atTheLatest
		atTheLatest = new Date(1000 * atTheLatest).getTime()
		delete message.at

		payload = JSON.stringify({
			stamp: scheduledFor.getTime(),
			event: {
				name: event.name
			},
			data: message
		})
		return punctual.Task.create {
        	type: 'pushMessage',
        	scheduledFor: scheduledFor,
        	atTheLatest: atTheLatest,
        	environment: 'production',
        	tagger: 'pushMessage',
        	active: true,
        	message: payload,
        	createdAt: new Date().getTime()
    	}

	messageFromTask: (task) =>
		try
			now = new Date().getTime()

			# parse payload
			message = JSON.parse(task.message)
			stamp = message.stamp
			event = message.event
			data = message.data

			# parse meta
			at = +stamp
			atTheLatest = at + @maxRetain
			if task.atTheLatest? && +(task.atTheLatest)
				atTheLatest = +task.atTheLatest
			atTheLatest = new Date(atTheLatest).getTime()
			at = new Date(at).getTime()

			# drop tasks that are outdated or inactive
			if (!task.active) || (now > atTheLatest) || (now > at)
				return null
			return message
		catch ex
	    	@logger.error "could not create message from task #{ex} #{ex.stack}"
	    	return null

	scheduleMessage: (event, data, cb) ->
		task = @taskFromMessage(event, data)
		@taskDAO.saveTask task, (err, task) =>
	       	@logger.verbose("scheduled message #{task.id}")
	       	if cb
	       		if err?
	       			cb(-1)
	       		else
	       			cb(0, task && task.id)

	removeMessage: (id, cb) ->
		@taskDAO.removeTaskById id, (err, replies) ->
			if err?
				cb(err, replies)
			else
				cb()

	updateMessage: (id, data, cb) ->
		@taskDAO.updateTaskById id, data, (err, newTask) ->
			if err?
				cb(err, replies)
			else
				cb(null, newTask)

	getMessage: (id, cb) =>
		@taskDAO.getTaskById id, (err, taskObj) =>
			if err?
				cb(err)
			else
				message = @messageFromTask(taskObj)
				if message?
					message.id = taskObj.id
					cb(null, message)
				else
					cb('outdated')

exports.EventScheduler = EventScheduler	
