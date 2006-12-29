#!/usr/bin/env ruby
#
#  Created by Luke A. Kanies on 2006-11-24.
#  Copyright (c) 2006. All rights reserved.

require 'puppet/gratr/digraph'
require 'puppet/gratr/import'
require 'puppet/gratr/dot'
require 'puppet/relationship'

# This class subclasses a graph class in order to handle relationships
# among resources.
class Puppet::PGraph < GRATR::Digraph
    # This is the type used for splicing.
    attr_accessor :container_type

    include Puppet::Util

    def add_edge!(*args)
        @reversal = nil
        super
    end

    def add_vertex!(*args)
        @reversal = nil
        super
    end
    
    def clear
        @vertex_dict.clear
        if defined? @edge_number
            @edge_number.clear
        end
    end

    # Which resources a given resource depends upon.
    def dependents(resource)
        tree_from_vertex2(resource).keys
    end
    
    # Which resources depend upon the given resource.
    def dependencies(resource)
        # Cache the reversal graph, because it's somewhat expensive
        # to create.
        unless defined? @reversal and @reversal
            @reversal = reversal
        end
        # Strangely, it's significantly faster to search a reversed
        # tree in the :out direction than to search a normal tree
        # in the :in direction.
        @reversal.tree_from_vertex2(resource, :out).keys
        #tree_from_vertex2(resource, :in).keys
    end
    
    # Override this method to use our class instead.
    def edge_class()
        Puppet::Relationship
    end
    
    # Determine all of the leaf nodes below a given vertex.
    def leaves(vertex, type = :dfs)
        tree = tree_from_vertex(vertex, type)
        l = tree.keys.find_all { |c| adjacent(c, :direction => :out).empty? }
        return l
    end
    
    # Collect all of the edges that the passed events match.  Returns
    # an array of edges.
    def matching_edges(events, base = nil)
        events.collect do |event|
            source = base || event.source
            
            unless vertex?(source)
                Puppet.warning "Got an event from invalid vertex %s" % source.ref
                next
            end
            # Get all of the edges that this vertex should forward events
            # to, which is the same thing as saying all edges directly below
            # This vertex in the graph.
            adjacent(source, :direction => :out, :type => :edges).find_all do |edge|
                edge.match?(event.event)
            end.each { |edge|
                target = edge.target
                if target.respond_to?(:ref)
                    source.info "Scheduling %s of %s" %
                        [edge.callback, target.ref]
                end
            }
        end.flatten
    end
    
    # Take container information from another graph and use it
    # to replace any container vertices with their respective leaves.
    # This creates direct relationships where there were previously
    # indirect relationships through the containers. 
    def splice!(other, type)
        vertices.find_all { |v| v.is_a?(type) }.each do |vertex|
            # Get the list of children from the other graph.
            #children = other.adjacent(vertex, :direction => :out)
            children = other.leaves(vertex)

            # Just remove the container if it's empty.
            if children.empty?
                remove_vertex!(vertex)
                next
            end
            
            # First create new edges for each of the :in edges
            [:in, :out].each do |dir|
                adjacent(vertex, :direction => dir, :type => :edges).each do |edge|
                    if dir == :in
                        nvertex = edge.source
                    else
                        nvertex = edge.target
                    end
                    if nvertex.is_a?(type)
                        neighbors = other.leaves(nvertex)
                    else
                        neighbors = [nvertex]
                    end

                    children.each do |child|
                        neighbors.each do |neighbor|
                            if dir == :in
                                s = neighbor
                                t = child
                            else
                                s = child
                                t = neighbor
                            end
                            if s.is_a?(type)
                                raise "Source %s is still a container" % s
                            end
                            if t.is_a?(type)
                                raise "Target %s is still a container" % t
                            end

                            # It *appears* that we're having a problem
                            # with multigraphs.
                            next if edge?(s, t)
                            add_edge!(s, t, edge.label)
                            if cyclic?
                                raise ArgumentError,
                                    "%s => %s results in a loop" %
                                    [s, t]
                            end
                        end
                    end
                end
            end
            remove_vertex!(vertex)
        end
    end
    
    # For some reason, unconnected vertices do not show up in
    # this graph.
    def to_jpg(path, name)
        gv = vertices()
        Dir.chdir(path) do
            induced_subgraph(gv).write_to_graphic_file('jpg', name)
        end
    end

    # A different way of walking a tree, and a much faster way than the
    # one that comes with GRATR.
    def tree_from_vertex2(start, direction = :out)
        predecessor={}
        walk(start, direction) do |parent, child|
            predecessor[child] = parent
        end
        predecessor       
    end

    # A support method for tree_from_vertex2.  Just walk the tree and pass
    # the parents and children.
    def walk(source, direction, &block)
        adjacent(source, :direction => direction).each do |target|
            yield source, target
            walk(target, direction, &block)
        end
    end
end

# $Id$
